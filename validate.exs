#!/usr/bin/env elixir

defmodule SchemaValidator do
  @moduledoc """
  Parallel schema validation for YAML and JSON files.
  """

  @schema_annotation_regex ~r/\$schema"?[=:]\s*"?([^"\s]+)"?/
  @cache_dir "tmp/cache/schemas"

  defmodule Summary do
    @moduledoc false
    @type t :: %__MODULE__{
            total_files: non_neg_integer(),
            passed_files: non_neg_integer(),
            failed_files: non_neg_integer(),
            errors: [String.t()]
          }
    defstruct [:total_files, :passed_files, :failed_files, :errors]

    def new do
      %__MODULE__{
        total_files: 0,
        passed_files: 0,
        failed_files: 0,
        errors: []
      }
    end
  end

  def main do
    args = System.argv()
    trace_mode = "--trace" in args
    clear_cache = "--clear-cache" in args

    if clear_cache do
      clear_schema_cache()
      IO.puts("🗑️  Cache cleared successfully!")
      System.halt(0)
    end

    ensure_cache_dir()
    IO.puts("🔍 Validating files with schema annotations...")

    files = files_with_schemas()

    # Process files - either in parallel or sequentially with trace
    summary =
      if trace_mode do
        IO.puts("🔍 Running in trace mode (concurrency: 1)...")

        files
        |> Enum.map(&validate_file_with_trace/1)
        |> calculate_summary()
      else
        files
        |> Task.async_stream(&validate_file/1,
          max_concurrency: min(25, max(10, System.schedulers_online() * 3)),
          timeout: 30_000,
          on_timeout: :kill_task
        )
        |> Enum.map(fn
          {:ok, result} -> result
          {:exit, reason} -> {:error, "Process timeout or crash: #{inspect(reason)}"}
        end)
        |> calculate_summary()
      end

    IO.puts("\n")

    print_summary(summary)

    if summary.failed_files > 0 do
      System.halt(1)
    else
      System.halt(0)
    end
  end

  defp files_with_schemas do
    ["**/*.yaml", "**/*.yml", "**/*.json"]
    |> Enum.flat_map(&Path.wildcard/1)
    |> Enum.reject(&String.contains?(&1, "node_modules"))
    |> Enum.filter(&has_schema_annotation?/1)
  end

  defp has_schema_annotation?(file) do
    case File.read(file) do
      {:ok, content} -> Regex.match?(@schema_annotation_regex, content)
      {:error, _} -> false
    end
  end

  defp extract_schema_url(file) do
    case File.read(file) do
      {:ok, content} ->
        Regex.run(@schema_annotation_regex, content, capture: :all_but_first)
        |> case do
          [url] -> url
          _ -> nil
        end

      {:error, _} ->
        nil
    end
  end

  defp validate_file(file) do
    schema_url = extract_schema_url(file)

    if schema_url do
      cached_schema = get_cached_schema(schema_url)

      case System.cmd("check-jsonschema", ["--schemafile", cached_schema, file],
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

  defp validate_file_with_trace(file) do
    IO.puts("Validating: #{file}")

    schema_url = extract_schema_url(file)

    if schema_url do
      cached_schema = get_cached_schema(schema_url)
      IO.puts("  Using schema: #{cached_schema}")

      case System.cmd("check-jsonschema", ["--schemafile", cached_schema, file],
             stderr_to_stdout: true
           ) do
        {_output, 0} ->
          IO.puts("  ✅ Passed")
          {:ok, file}

        {_output, _exit_code} ->
          IO.puts("  ❌ Failed")
          {:error, file}
      end
    else
      IO.puts("  ❌ Failed (no schema found)")
      {:error, file}
    end
  end

  defp calculate_summary(results) do
    summary = Summary.new()

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

  defp ensure_cache_dir do
    File.mkdir_p!(@cache_dir)
  end

  defp clear_schema_cache do
    if File.exists?(@cache_dir) do
      File.rm_rf!(@cache_dir)
    end

    File.mkdir_p!(@cache_dir)
  end

  defp get_cached_schema(schema_url) do
    cache_filename =
      schema_url
      |> String.replace([":", "/", "?", "=", "&"], "_")
      |> String.replace("__", "_")
      |> then(&"#{&1}.json")

    cache_path = Path.join(@cache_dir, cache_filename)

    if File.exists?(cache_path) do
      cache_path
    else
      download_and_cache_schema(schema_url, cache_path)
    end
  end

  defp download_and_cache_schema(schema_url, cache_path) do
    case System.cmd("curl", ["-s", "-L", "-o", cache_path, schema_url]) do
      {_, 0} -> cache_path
      # Fall back to original URL if download fails
      {_, _} -> schema_url
    end
  end
end

SchemaValidator.main()
