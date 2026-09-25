#!/usr/bin/env elixir

defmodule HelmExternalSecretValidator do
  @moduledoc false

  @expression ~r/\{\{-?\s*(?:\.[A-Za-z_][A-Za-z_0-9]*|index\s+\.\s+["'][^"']+["'])\s*-?\}\}/

  def main(args) do
    charts = if args == [], do: local_charts(), else: args

    errors = Enum.flat_map(charts, &check_chart/1)

    if errors == [] do
      IO.puts("Helm preserved ExternalSecret expressions in #{length(charts)} local chart(s).")
    else
      Enum.each(errors, &IO.puts(:stderr, &1))
      System.halt(1)
    end
  end

  defp local_charts do
    {output, 0} =
      System.cmd("git", [
        "ls-files",
        "--cached",
        "--others",
        "--exclude-standard",
        "--",
        "Chart.yaml",
        "**/Chart.yaml"
      ])

    output
    |> String.split("\n", trim: true)
    |> Enum.map(&Path.dirname/1)
    |> Enum.uniq()
  end

  defp check_chart(chart) do
    chart
    |> Path.join("templates/**/*.yaml")
    |> Path.wildcard()
    |> Kernel.++(Path.wildcard(Path.join(chart, "templates/**/*.yml")))
    |> Enum.flat_map(&check_template(chart, &1))
  end

  defp check_template(chart, template) do
    source = File.read!(template)

    expressions =
      if String.contains?(source, "kind: ExternalSecret"),
        do: Regex.scan(@expression, source) |> List.flatten() |> Enum.frequencies(),
        else: %{}

    if expressions == %{} do
      []
    else
      relative = Path.relative_to(template, chart)

      case System.cmd("helm", ["template", Path.basename(chart), chart, "--show-only", relative],
             stderr_to_stdout: true
           ) do
        {rendered, 0} ->
          # Ignore comments: a YAML comment with the same expression is not a usable Secret value.
          content =
            rendered
            |> String.split("\n")
            |> Enum.reject(&(String.trim_leading(&1) |> String.starts_with?("#")))
            |> Enum.join("\n")

          for {expression, expected} <- expressions,
              actual = content |> String.split(expression) |> length() |> Kernel.-(1),
              actual < expected do
            "#{template}: Helm consumed #{expected - actual} occurrence(s) of #{expression}; escape it or use spec.data with remoteRef.property"
          end

        {error, _status} ->
          ["#{template}: Helm render failed: #{String.trim(error)}"]
      end
    end
  end
end

HelmExternalSecretValidator.main(System.argv())
