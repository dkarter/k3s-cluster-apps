ExUnit.start()

defmodule ValidatorChecksTest do
  use ExUnit.Case, async: false

  @repo_root Path.expand("..", __DIR__)
  @crd_script Path.join(@repo_root, "validate-crd-schema-annotations.exs")
  @values_script Path.join(@repo_root, "validate-values-schema-annotations.exs")

  test "values schema check fails when a chart update leaves a pinned values schema behind" do
    in_tmp_repo(fn repo ->
      write_app(repo, "4.6.2")

      write_file(repo, "apps/demo/values.yml", """
      # yaml-language-server: $schema=https://raw.githubusercontent.com/bjw-s-labs/helm-charts/app-template-4.6.2/charts/other/app-template/values.schema.json
      controllers: {}
      """)

      git!(repo, ["add", "."])
      git!(repo, ["commit", "-m", "base"])
      base_ref = git_output!(repo, ["rev-parse", "HEAD"])

      write_app(repo, "4.7.0")

      {output, status} = run_script(repo, @values_script, base_ref: base_ref)

      assert status == 1
      assert output =~ "stale yaml-language-server values schema annotations"
      assert output =~ "apps/demo/values.yml: app-template annotation is 4.6.2, chart is 4.7.0"
    end)
  end

  test "values schema check passes for unversioned CRD schemas" do
    in_tmp_repo(fn repo ->
      write_external_secrets_app(repo, "1.3.2")

      write_file(repo, "demo/external-secret.yml", """
      # yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/external-secrets.io/externalsecret_v1.json
      apiVersion: external-secrets.io/v1
      kind: ExternalSecret
      """)

      git!(repo, ["add", "."])
      git!(repo, ["commit", "-m", "base"])
      base_ref = git_output!(repo, ["rev-parse", "HEAD"])

      write_external_secrets_app(repo, "2.4.0")

      {output, status} = run_script(repo, @values_script, base_ref: base_ref)

      assert status == 0
      assert output =~ "No stale Helm values schema annotations detected."
    end)
  end

  test "values schema check compares feature branches to origin main by default" do
    in_tmp_repo(fn repo ->
      write_app(repo, "4.6.2")

      write_file(repo, "apps/demo/values.yml", """
      # yaml-language-server: $schema=https://raw.githubusercontent.com/bjw-s-labs/helm-charts/app-template-4.6.2/charts/other/app-template/values.schema.json
      controllers: {}
      """)

      git!(repo, ["add", "."])
      git!(repo, ["commit", "-m", "base"])
      git!(repo, ["update-ref", "refs/remotes/origin/main", "HEAD"])
      git!(repo, ["checkout", "-b", "feature/schema-drift"])

      write_app(repo, "4.7.0")
      git!(repo, ["add", "."])
      git!(repo, ["commit", "-m", "update chart"])

      {output, status} = run_script(repo, @values_script, env: [{"GITHUB_BASE_REF", ""}])

      assert status == 1
      assert output =~ "apps/demo/values.yml: app-template annotation is 4.6.2, chart is 4.7.0"
    end)
  end

  test "CRD check ignores CRD schema content changes that keep the same schema targets" do
    in_tmp_repo(fn repo ->
      write_external_secrets_app(repo, "1.3.2")
      git!(repo, ["add", "."])
      git!(repo, ["commit", "-m", "base"])
      base_ref = git_output!(repo, ["rev-parse", "HEAD"])
      write_external_secrets_app(repo, "2.4.0")

      {output, status} =
        run_script(repo, @crd_script,
          bin_path: helm_path(repo, :same_targets),
          base_ref: base_ref
        )

      assert status == 0
      assert output =~ "No Helm chart CRD updates detected."
    end)
  end

  test "CRD check fails when a chart update changes CRD schema targets" do
    in_tmp_repo(fn repo ->
      write_external_secrets_app(repo, "1.3.2")
      git!(repo, ["add", "."])
      git!(repo, ["commit", "-m", "base"])
      base_ref = git_output!(repo, ["rev-parse", "HEAD"])
      write_external_secrets_app(repo, "2.4.0")

      {output, status} =
        run_script(repo, @crd_script,
          bin_path: helm_path(repo, :changed_targets),
          base_ref: base_ref
        )

      assert status == 1
      assert output =~ "Helm chart CRD updates detected"
      assert output =~ "external-secrets 1.3.2 -> 2.4.0 (external-secrets.io)"
    end)
  end

  test "CRD check reports worker errors instead of ignoring them" do
    in_tmp_repo(fn repo ->
      write_external_secrets_app(repo, "1.3.2")
      git!(repo, ["add", "."])
      git!(repo, ["commit", "-m", "base"])
      base_ref = git_output!(repo, ["rev-parse", "HEAD"])
      write_external_secrets_app(repo, "2.4.0")

      cache_file =
        Path.join(
          repo,
          "tmp/cache/helm-crd-targets/https_charts.external-secrets.io_external-secrets_1.3.2.txt"
        )

      File.mkdir_p!(cache_file)

      {output, status} =
        run_script(repo, @crd_script,
          bin_path: helm_path(repo, :same_targets),
          base_ref: base_ref
        )

      assert status == 2, output
      assert output =~ "Failed while checking Helm chart CRD updates."
    end)
  end

  defp in_tmp_repo(fun) do
    repo = Path.join(System.tmp_dir!(), "validator-checks-#{System.unique_integer([:positive])}")
    File.rm_rf!(repo)
    File.mkdir_p!(repo)

    try do
      git!(repo, ["init", "-b", "main"])
      git!(repo, ["config", "user.email", "tests@example.invalid"])
      git!(repo, ["config", "user.name", "Validator Tests"])
      fun.(repo)
    after
      File.rm_rf!(repo)
    end
  end

  defp write_app(repo, version) do
    write_file(repo, "apps/demo/application.yml", """
    apiVersion: argoproj.io/v1alpha1
    kind: Application
    spec:
      sources:
        - repoURL: 'https://github.com/example/repo.git'
          targetRevision: HEAD
          ref: values

        - chart: app-template
          repoURL: https://bjw-s-labs.github.io/helm-charts
          targetRevision: #{version}
          helm:
            valueFiles:
              - $values/apps/demo/values.yml
    """)
  end

  defp write_external_secrets_app(repo, version) do
    write_file(repo, "apps/external-secrets.yml", """
    apiVersion: argoproj.io/v1alpha1
    kind: Application
    spec:
      sources:
        - chart: external-secrets
          repoURL: https://charts.external-secrets.io
          targetRevision: #{version}
    """)
  end

  defp write_file(repo, path, content) do
    file = Path.join(repo, path)
    file |> Path.dirname() |> File.mkdir_p!()
    File.write!(file, content)
  end

  defp run_script(repo, script, opts) do
    env = opts[:env] || []

    env = if base_ref = opts[:base_ref], do: [{"BASE_REF", base_ref} | env], else: env

    env =
      if bin_path = opts[:bin_path],
        do: [{"PATH", "#{bin_path}:#{System.get_env("PATH")}"} | env],
        else: env

    System.cmd(script, [], cd: repo, env: env, stderr_to_stdout: true)
  end

  defp git!(repo, args) do
    case System.cmd("git", args, cd: repo, stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, status} -> flunk("git #{Enum.join(args, " ")} failed with #{status}:\n#{output}")
    end
  end

  defp git_output!(repo, args) do
    case System.cmd("git", args, cd: repo, stderr_to_stdout: true) do
      {output, 0} -> String.trim(output)
      {output, status} -> flunk("git #{Enum.join(args, " ")} failed with #{status}:\n#{output}")
    end
  end

  defp helm_path(repo, mode) do
    bin = Path.join(repo, "bin")
    File.mkdir_p!(bin)

    write_file(repo, "bin/helm", """
    #!/usr/bin/env sh
    version=""

    while [ "$#" -gt 0 ]; do
      if [ "$1" = "--version" ]; then
        shift
        version="$1"
      fi

      shift
    done

    if [ "#{mode}" = "same_targets" ]; then
      kind="ExternalSecret"
      api="v1"
    elif [ "$version" = "1.3.2" ]; then
      kind="ExternalSecret"
      api="v1"
    else
      kind="ClusterExternalSecret"
      api="v1beta1"
    fi

    cat <<EOF
    ---
    apiVersion: apiextensions.k8s.io/v1
    kind: CustomResourceDefinition
    metadata:
      name: examples.external-secrets.io
    spec:
      group: external-secrets.io
      names:
        kind: $kind
      versions:
        - name: $api
          schema:
            openAPIV3Schema:
              type: object
    EOF
    """)

    Path.join(repo, "bin/helm") |> File.chmod!(0o755)
    bin
  end
end
