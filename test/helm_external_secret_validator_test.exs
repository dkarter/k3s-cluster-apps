ExUnit.start()

defmodule HelmExternalSecretValidatorTest do
  use ExUnit.Case, async: false

  @validator Path.expand("../validate-helm-external-secrets.exs", __DIR__)

  test "rejects expressions consumed by Helm" do
    with_chart("PAPERLESS_SECRET_KEY: '{{ .PAPERLESS_SECRET_KEY }}'", fn chart ->
      {output, status} = run_validator(chart)
      assert status == 1
      assert output =~ "Helm consumed 1 occurrence(s) of {{ .PAPERLESS_SECRET_KEY }}"
    end)
  end

  test "accepts escaped expressions preserved for External Secrets" do
    with_chart("PAPERLESS_SECRET_KEY: '{{ `{{ .PAPERLESS_SECRET_KEY }}` }}'", fn chart ->
      {output, status} = run_validator(chart)
      assert status == 0, output
    end)
  end

  test "rejects unescaped index expressions for fields with dashes" do
    with_chart(~s(PAPERLESS_SECRET_KEY: '{{ index . "secret-key" }}'), fn chart ->
      {output, status} = run_validator(chart)
      assert status == 1
      assert output =~ "Helm consumed"
    end)
  end

  test "rejects whitespace-trimmed expressions consumed by Helm" do
    with_chart("PAPERLESS_SECRET_KEY: '{{- .PAPERLESS_SECRET_KEY -}}'", fn chart ->
      {output, status} = run_validator(chart)
      assert status == 1
      assert output =~ "Helm consumed"
    end)
  end

  test "requires every occurrence to survive rendering" do
    with_chart(
      "PAPERLESS_SECRET_KEY: '{{ .PAPERLESS_SECRET_KEY }} {{ `{{ .PAPERLESS_SECRET_KEY }}` }}'",
      fn chart ->
        {output, status} = run_validator(chart)
        assert status == 1
        assert output =~ "1 occurrence(s)"
      end
    )
  end

  test "accepts explicit field mappings without a second template language" do
    with_chart(
      "data:\n    - secretKey: PAPERLESS_SECRET_KEY\n      remoteRef:\n        key: paperless\n        property: PAPERLESS_SECRET_KEY",
      fn chart ->
        {output, status} = run_validator(chart)
        assert status == 0, output
      end
    )
  end

  defp with_chart(data, fun) do
    chart =
      Path.join(
        System.tmp_dir!(),
        "external-secret-validator-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(Path.join(chart, "templates"))
    File.write!(Path.join(chart, "Chart.yaml"), "apiVersion: v2\nname: example\nversion: 0.1.0\n")

    File.write!(Path.join(chart, "templates/external-secret.yaml"), """
    apiVersion: external-secrets.io/v1
    kind: ExternalSecret
    metadata:
      name: example
    spec:
      target:
        template:
          data:
            #{data}
    """)

    try do
      fun.(chart)
    after
      File.rm_rf!(chart)
    end
  end

  defp run_validator(chart) do
    System.cmd("elixir", [@validator, chart], stderr_to_stdout: true)
  end
end
