#!/usr/bin/env elixir

defmodule SchemaValidator do
  @moduledoc """
  Parallel schema validation for YAML and JSON files.
  Maintains compatibility with the existing bash validation output format.
  """

  defstruct [:total_files, :passed_files, :failed_files, :errors]

  def new do
    %__MODULE__{
      total_files: 0,
      passed_files: 0,
      failed_files: 0,
      errors: []
    }
  end

  def main do
    IO.puts("🔍 Validating files with schema annotations...")

    files_with_schemas = find_files_with_schemas()

    if Enum.empty?(files_with_schemas) do
      IO.puts("\n📊 Summary:")
      IO.puts("  Total files: 0")
      IO.puts("  Passed: 0")
      IO.puts("  Failed: 0")
      IO.puts("\n✅ No files with schema annotations found!")
      System.halt(0)
    end

    # Process files in parallel
    results =
      files_with_schemas
      |> Task.async_stream(&validate_file/1,
        max_concurrency: min(25, max(10, System.schedulers_online() * 3)),
        timeout: 30_000,
        on_timeout: :kill_task
      )
      |> Enum.map(fn
        {:ok, result} -> result
        {:exit, reason} -> {:error, "Process timeout or crash: #{inspect(reason)}"}
      end)

    IO.puts("\n")

    # Calculate summary
    summary = calculate_summary(results)

    # Print summary
    print_summary(summary)

    # Exit with appropriate code
    if summary.failed_files > 0 do
      System.halt(1)
    else
      System.halt(0)
    end
  end

  defp find_files_with_schemas do
    yaml_files = find_yaml_files_with_schemas()
    json_files = find_json_files_with_schemas()

    yaml_files ++ json_files
  end

  defp find_yaml_files_with_schemas do
    ["**/*.yaml", "**/*.yml"]
    |> Enum.flat_map(&Path.wildcard/1)
    |> Enum.reject(&String.contains?(&1, "node_modules"))
    |> Enum.filter(&has_yaml_schema_annotation?/1)
    |> Enum.map(&{&1, :yaml})
  end

  defp find_json_files_with_schemas do
    Path.wildcard("**/*.json")
    |> Enum.reject(&String.contains?(&1, "node_modules"))
    |> Enum.filter(&has_json_schema_annotation?/1)
    |> Enum.map(&{&1, :json})
  end

  defp has_yaml_schema_annotation?(file) do
    case File.read(file) do
      {:ok, content} ->
        content
        |> String.split("\n")
        |> Enum.any?(&String.match?(&1, ~r/^\s*#.*yaml-language-server.*schema=/))

      {:error, _} ->
        false
    end
  end

  defp has_json_schema_annotation?(file) do
    case File.read(file) do
      {:ok, content} -> String.contains?(content, "\"$schema\"")
      {:error, _} -> false
    end
  end

  defp extract_schema_url(file, :yaml) do
    case File.read(file) do
      {:ok, content} ->
        content
        |> String.split("\n")
        |> Enum.find_value(fn line ->
          if String.match?(line, ~r/^\s*#.*yaml-language-server.*schema=/) do
            Regex.run(~r/schema=([^\s]+)/, line, capture: :all_but_first)
            |> case do
              [url] -> url
              _ -> nil
            end
          end
        end)

      {:error, _} ->
        nil
    end
  end

  defp extract_schema_url(file, :json) do
    case File.read(file) do
      {:ok, content} ->
        Regex.run(~r/"\$schema"\s*:\s*"([^"]+)"/, content, capture: :all_but_first)
        |> case do
          [url] -> url
          _ -> nil
        end

      {:error, _} ->
        nil
    end
  end

  defp validate_file({file, type}) do
    schema_url = extract_schema_url(file, type)

    if schema_url do
      case System.cmd("check-jsonschema", ["--schemafile", schema_url, file],
             stderr_to_stdout: true
           ) do
        {_output, 0} -> {:ok, file}
        {_output, _exit_code} -> {:error, file}
      end
    else
      {:error, file}
    end
    |> tap(fn
      {:ok, _file} -> IO.write("\e[32m.\e[0m")
      {:error, _file} -> IO.write("\e[31mX\e[0m")
    end)
  end

  defp calculate_summary(results) do
    summary = new()

    Enum.reduce(results, summary, fn result, acc ->
      case result do
        {:ok, _file} ->
          %{acc | total_files: acc.total_files + 1, passed_files: acc.passed_files + 1}

        {:error, file} ->
          %{
            acc
            | total_files: acc.total_files + 1,
              failed_files: acc.failed_files + 1,
              errors: [file | acc.errors]
          }
      end
    end)
    |> then(&%{&1 | errors: Enum.reverse(&1.errors)})
  end

  defp print_summary(summary) do
    IO.puts("📊 Summary:")
    IO.puts("  Total files: #{summary.total_files}")
    IO.puts("  Passed: #{summary.passed_files}")
    IO.puts("  Failed: #{summary.failed_files}")

    if summary.failed_files > 0 do
      IO.puts("")
      IO.puts("❌ Failures:")

      Enum.each(summary.errors, fn error ->
        IO.puts("  #{error} (schema validation failed)")
      end)
    else
      IO.puts("")
      IO.puts("✅ All files passed validation!")
    end
  end
end

SchemaValidator.main()
