defmodule ValidatorUtils do
  @moduledoc false

  def base_ref do
    env_ref("BASE_REF") ||
      env_ref("GITHUB_BASE_REF") ||
      default_base_ref()
  end

  def comparison_base do
    base_ref = base_ref()

    if current_branch() in ["main", "master"] do
      base_ref
    else
      case cmd("git", ["merge-base", "HEAD", base_ref]) do
        {commit, 0} -> String.trim(commit)
        _ -> base_ref
      end
    end
  end

  def changed_files(base_commit) do
    [
      git_lines(["diff", "--name-only", "#{base_commit}...HEAD"]),
      git_lines(["diff", "--name-only"]),
      git_lines(["diff", "--cached", "--name-only"])
    ]
    |> List.flatten()
    |> Enum.uniq()
    |> Enum.filter(&(&1 != ""))
  end

  def changed_diff(base_commit) do
    [
      git_diff(["diff", "#{base_commit}...HEAD"]),
      git_diff(["diff"]),
      git_diff(["diff", "--cached"])
    ]
    |> Enum.join("\n")
  end

  def file_at_ref(ref, file) do
    case cmd("git", ["show", "#{ref}:#{file}"]) do
      {content, 0} -> content
      _ -> ""
    end
  end

  def git_diff(args) do
    case cmd("git", args) do
      {output, 0} -> output
      _ -> ""
    end
  end

  def cmd(command, args), do: System.cmd(command, args, stderr_to_stdout: true)

  defp env_ref(name) do
    case System.get_env(name) do
      nil -> nil
      value -> if String.trim(value) == "", do: nil, else: value
    end
  end

  defp default_base_ref do
    case current_branch() do
      "master" -> "origin/master"
      _ -> "origin/main"
    end
  end

  defp current_branch do
    case cmd("git", ["branch", "--show-current"]) do
      {branch, 0} -> String.trim(branch)
      _ -> ""
    end
  end

  defp git_lines(args) do
    args |> git_diff() |> String.split("\n", trim: true)
  end
end
