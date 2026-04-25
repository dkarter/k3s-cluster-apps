#!/usr/bin/env elixir

defmodule ValuesSchemaAnnotationValidator do
  @moduledoc false

  @app_file_regex ~r|^apps/.+\.ya?ml$|

  def main do
    base_commit = base_ref() |> merge_base()

    mismatches =
      base_commit
      |> changed_files()
      |> Enum.filter(&Regex.match?(@app_file_regex, &1))
      |> Enum.flat_map(&changed_chart_sources(&1, base_commit))
      |> Enum.flat_map(&value_schema_mismatches/1)

    if mismatches == [] do
      IO.puts("No stale Helm values schema annotations detected.")
      System.halt(0)
    else
      IO.puts(
        "Helm chart updates detected with stale yaml-language-server values schema annotations."
      )

      IO.puts("")
      IO.puts("Update these values schema annotations to match their chart targetRevision:")

      Enum.each(mismatches, fn mismatch ->
        IO.puts(
          "- #{mismatch.values_file}: #{mismatch.chart} annotation is #{mismatch.schema_version}, chart is #{mismatch.chart_version}"
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
        Regex.match?(~r/^\s{4}-\s+/, line) ->
          current = finish_source(current)

          {append_source(sources, current),
           parse_source_line(%{file: file, value_files: []}, line)}

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
      Map.merge(%{version: nil, old_version: nil, new_version: nil, value_files: []}, source)
    end
  end

  defp append_source(sources, nil), do: sources
  defp append_source(sources, source), do: [source | sources]

  defp parse_source_line(source, line) do
    cond do
      value = line_value(line, "chart") -> Map.put(source, :chart, value)
      value = line_value(line, "repoURL") -> Map.put(source, :repo, value)
      value = line_value(line, "targetRevision") -> Map.put(source, :version, value)
      value = values_file(line) -> Map.update!(source, :value_files, &[value | &1])
      true -> source
    end
  end

  defp line_value(line, key) do
    case Regex.run(~r/^\s*(?:-\s+)?#{key}:\s*["']?([^"'\s]+)["']?\s*$/, line) do
      [_, value] -> value
      _ -> nil
    end
  end

  defp values_file(line) do
    case Regex.run(~r/^\s*-\s+\$values\/(.+\.ya?ml)\s*$/, line) do
      [_, value] -> value
      _ -> nil
    end
  end

  defp value_schema_mismatches(source) do
    source.value_files
    |> Enum.reverse()
    |> Enum.flat_map(fn values_file ->
      with {:ok, content} <- File.read(values_file),
           schema_url when is_binary(schema_url) <- schema_url(content),
           schema_version when is_binary(schema_version) <-
             schema_chart_version(schema_url, source.chart),
           true <- schema_version != source.new_version do
        [
          %{
            chart: source.chart,
            chart_version: source.new_version,
            schema_version: schema_version,
            values_file: values_file
          }
        ]
      else
        _ -> []
      end
    end)
  end

  defp schema_url(content) do
    case Regex.run(~r/yaml-language-server:\s*\$schema=([^\s]+)/, content) do
      [_, url] -> url
      _ -> nil
    end
  end

  defp schema_chart_version(schema_url, chart) do
    regex = Regex.compile!("#{Regex.escape(chart)}-([^/]+)/")

    case Regex.run(regex, schema_url) do
      [_, version] -> version
      _ -> nil
    end
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

ValuesSchemaAnnotationValidator.main()
