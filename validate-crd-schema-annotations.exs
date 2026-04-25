#!/usr/bin/env elixir

defmodule CrdSchemaAnnotationValidator do
  @moduledoc false

  @app_file_regex ~r|^apps/.+\.ya?ml$|
  @schema_annotation_regex ~r/yaml-language-server:\s*\$schema=/

  def main do
    base_ref = base_ref()
    base_commit = merge_base(base_ref)

    changed_app_files =
      changed_files(base_commit) |> Enum.filter(&Regex.match?(@app_file_regex, &1))

    crd_updates =
      changed_app_files
      |> Enum.flat_map(&changed_chart_sources(&1, base_commit))
      |> Task.async_stream(&with_crd_changes/1,
        max_concurrency: min(8, max(2, System.schedulers_online())),
        timeout: 120_000,
        on_timeout: :kill_task
      )
      |> Enum.flat_map(fn
        {:ok, nil} -> []
        {:ok, source} -> [source]
        {:exit, _reason} -> []
      end)

    cond do
      crd_updates == [] ->
        IO.puts("No Helm chart CRD updates detected.")
        System.halt(0)

      schema_annotations_changed?(base_commit, crd_updates) ->
        IO.puts("Helm chart CRD updates detected with yaml-language-server annotation changes.")
        System.halt(0)

      true ->
        IO.puts(
          "Helm chart CRD updates detected, but no yaml-language-server schema annotations changed."
        )

        IO.puts("")

        IO.puts(
          "Update the relevant # yaml-language-server: $schema=... annotations for custom resources touched by these chart CRD changes:"
        )

        Enum.each(crd_updates, fn source ->
          groups = Enum.join(source.crd_groups, ", ")

          IO.puts(
            "- #{source.file}: #{source.chart} #{source.old_version || "<none>"} -> #{source.new_version}#{format_groups(groups)}"
          )
        end)

        System.halt(1)
    end
  end

  defp base_ref do
    System.get_env("BASE_REF") ||
      System.get_env("GITHUB_BASE_REF") ||
      "origin/main"
  end

  defp merge_base(base_ref) do
    case cmd("git", ["merge-base", "HEAD", base_ref]) do
      {commit, 0} -> String.trim(commit)
      _ -> base_ref
    end
  end

  defp changed_files(base_commit) do
    [
      git_lines(["diff", "--name-only", "#{base_commit}...HEAD"]),
      git_lines(["diff", "--name-only"]),
      git_lines(["diff", "--cached", "--name-only"])
    ]
    |> List.flatten()
    |> Enum.uniq()
    |> Enum.filter(&(&1 != ""))
  end

  defp changed_chart_sources(file, base_commit) do
    old_sources = file_at_ref(base_commit, file) |> parse_chart_sources(file)
    new_sources = file_at_worktree(file) |> parse_chart_sources(file)

    Enum.flat_map(new_sources, fn new_source ->
      old_source = Enum.find(old_sources, &same_chart_source?(&1, new_source))

      cond do
        is_nil(new_source.version) ->
          []

        is_nil(old_source) ->
          [%{new_source | old_version: nil, new_version: new_source.version}]

        old_source.version != new_source.version ->
          [%{new_source | old_version: old_source.version, new_version: new_source.version}]

        true ->
          []
      end
    end)
  end

  defp same_chart_source?(old_source, new_source) do
    old_source.chart == new_source.chart && old_source.repo == new_source.repo
  end

  defp file_at_ref(ref, file) do
    case cmd("git", ["show", "#{ref}:#{file}"]) do
      {content, 0} -> content
      _ -> ""
    end
  end

  defp file_at_worktree(file) do
    case File.read(file) do
      {:ok, content} -> content
      {:error, _} -> ""
    end
  end

  defp parse_chart_sources(content, file) do
    content
    |> String.split("\n")
    |> Enum.reduce({[], nil}, fn line, {sources, current} ->
      cond do
        Regex.match?(~r/^\s*-\s+/, line) ->
          current = finish_source(current)
          {append_source(sources, current), parse_source_line(%{file: file}, line)}

        current != nil ->
          {sources, parse_source_line(current, line)}

        true ->
          {sources, current}
      end
    end)
    |> then(fn {sources, current} -> append_source(sources, finish_source(current)) end)
  end

  defp finish_source(nil), do: nil

  defp finish_source(source) do
    if source[:chart] && source[:repo] do
      Map.merge(%{version: nil, old_version: nil, new_version: nil}, source)
    end
  end

  defp append_source(sources, nil), do: sources
  defp append_source(sources, source), do: [source | sources]

  defp parse_source_line(source, line) do
    cond do
      value = line_value(line, "chart") -> Map.put(source, :chart, value)
      value = line_value(line, "repoURL") -> Map.put(source, :repo, value)
      value = line_value(line, "targetRevision") -> Map.put(source, :version, value)
      true -> source
    end
  end

  defp line_value(line, key) do
    case Regex.run(~r/^\s*(?:-\s+)?#{key}:\s*["']?([^"'\s]+)["']?\s*$/, line) do
      [_, value] -> value
      _ -> nil
    end
  end

  defp with_crd_changes(source) do
    old_targets =
      if source.old_version, do: crd_schema_targets(source, source.old_version), else: []

    new_targets = crd_schema_targets(source, source.new_version)

    if new_targets != [] && old_targets != new_targets do
      Map.merge(source, %{
        old_crd_targets: old_targets,
        new_crd_targets: new_targets,
        crd_groups: crd_groups(new_targets)
      })
    end
  end

  defp crd_schema_targets(source, version) do
    source
    |> rendered_crds(version)
    |> split_crd_documents()
    |> Enum.flat_map(fn document ->
      with [group] <- Regex.run(~r/^\s*group:\s*([^\s]+)\s*$/m, document, capture: :all_but_first),
           [kind] <- Regex.run(~r/^\s*kind:\s*([^\s]+)\s*$/m, document, capture: :all_but_first) do
        document
        |> then(&Regex.scan(~r/^\s*-\s*name:\s*([^\s]+)\s*$/m, &1, capture: :all_but_first))
        |> List.flatten()
        |> Enum.map(&"#{group}/#{kind}/#{&1}")
      else
        _ -> []
      end
    end)
    |> Enum.sort()
  end

  defp rendered_crds(source, version) do
    source
    |> helm_crds(version)
    |> case do
      "" -> helm_template_crds(source, version)
      crds -> crds
    end
    |> normalize_crds()
  end

  defp helm_crds(source, version) do
    case cmd("helm", ["show", "crds", source.chart, "--repo", source.repo, "--version", version]) do
      {output, 0} -> String.trim(output)
      _ -> ""
    end
  end

  defp helm_template_crds(source, version) do
    case cmd("helm", [
           "template",
           source.chart,
           source.chart,
           "--repo",
           source.repo,
           "--version",
           version
         ]) do
      {output, 0} -> extract_crds(output)
      _ -> ""
    end
  end

  defp extract_crds(rendered_manifests) do
    rendered_manifests
    |> split_crd_documents()
    |> Enum.sort()
    |> Enum.join("\n---\n")
  end

  defp split_crd_documents(rendered_manifests) do
    rendered_manifests
    |> String.split(~r/^---\s*$/m)
    |> Enum.filter(fn document ->
      Regex.match?(~r/^apiVersion:\s*apiextensions\.k8s\.io\//m, document) &&
        Regex.match?(~r/^kind:\s*CustomResourceDefinition\s*$/m, document)
    end)
    |> Enum.map(&String.trim/1)
  end

  defp normalize_crds(crds) do
    crds
    |> String.replace(~r/helm\.sh\/chart:\s*.+/, "helm.sh/chart: <chart>")
    |> String.replace(
      ~r/app\.kubernetes\.io\/version:\s*.+/,
      "app.kubernetes.io/version: <version>"
    )
    |> String.replace(
      ~r/controller-gen\.kubebuilder\.io\/version:\s*.+/,
      "controller-gen.kubebuilder.io/version: <version>"
    )
    |> String.trim()
  end

  defp crd_groups(crd_targets) do
    crd_targets
    |> Enum.map(fn target -> target |> String.split("/", parts: 2) |> List.first() end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp format_groups(""), do: ""
  defp format_groups(groups), do: " (#{groups})"

  defp schema_annotations_changed?(base_commit, crd_updates) do
    changed_crd_groups = crd_updates |> Enum.flat_map(& &1.crd_groups) |> Enum.uniq()

    [
      git_diff(["diff", "#{base_commit}...HEAD"]),
      git_diff(["diff"]),
      git_diff(["diff", "--cached"])
    ]
    |> Enum.join("\n")
    |> String.split("\n")
    |> Enum.any?(fn line ->
      String.starts_with?(line, ["+", "-"]) && Regex.match?(@schema_annotation_regex, line) &&
        Enum.any?(changed_crd_groups, &String.contains?(line, &1))
    end)
  end

  defp git_lines(args) do
    args |> git_diff() |> String.split("\n", trim: true)
  end

  defp git_diff(args) do
    case cmd("git", args) do
      {output, 0} -> output
      _ -> ""
    end
  end

  defp cmd(command, args), do: System.cmd(command, args, stderr_to_stdout: true)
end

CrdSchemaAnnotationValidator.main()
