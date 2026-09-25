ExUnit.start()

defmodule SchemaValidatorTest do
  use ExUnit.Case, async: false

  @script Path.expand("../validate.exs", __DIR__)

  test "without paths, validates all annotated files" do
    in_tmp_dir(fn dir ->
      {output, status} = run_validator(dir, [])

      assert status == 1
      assert output =~ "Total files: 2"
      assert output =~ "invalid.yml (schema validation failed)"
    end)
  end

  test "with paths, validates only annotated selected files in normal or trace mode" do
    in_tmp_dir(fn dir ->
      for args <- [["valid.yaml", "unannotated.json"], ["--trace", "valid.yaml"]] do
        {output, status} = run_validator(dir, args)

        assert status == 0
        assert output =~ "Total files: 1"
        assert output =~ "Passed: 1"
      end
    end)
  end

  test "fails on a missing selected file" do
    in_tmp_dir(fn dir ->
      {output, status} = run_validator(dir, ["missing.yaml"])

      assert status == 2
      assert output =~ "Files not found: missing.yaml"
    end)
  end

  defp in_tmp_dir(fun) do
    dir = Path.join(System.tmp_dir!(), "schema-validator-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(dir, "bin"))
    File.mkdir_p!(Path.join(dir, "tmp/cache/schemas"))

    File.write!(Path.join(dir, "tmp/cache/schemas/https_example.invalid_schema.json.json"), "{}")

    File.write!(
      Path.join(dir, "valid.yaml"),
      "# yaml-language-server: $schema=https://example.invalid/schema.json\nvalue: ok\n"
    )

    File.write!(
      Path.join(dir, "invalid.yml"),
      "# yaml-language-server: $schema=https://example.invalid/schema.json\nvalue: bad\n"
    )

    File.write!(Path.join(dir, "unannotated.json"), "{}\n")

    validator = Path.join(dir, "bin/check-jsonschema")
    File.write!(validator, "#!/bin/sh\ncase \"$*\" in *invalid.yml*) exit 1;; esac\nexit 0\n")
    File.chmod!(validator, 0o755)

    try do
      fun.(dir)
    after
      File.rm_rf!(dir)
    end
  end

  defp run_validator(dir, args) do
    System.cmd("elixir", [@script | args],
      cd: dir,
      env: [{"PATH", "#{Path.join(dir, "bin")}:#{System.get_env("PATH")}"}],
      stderr_to_stdout: true
    )
  end
end
