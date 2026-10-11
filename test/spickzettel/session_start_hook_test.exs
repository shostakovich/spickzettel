defmodule Spickzettel.SessionStartHookTest do
  use ExUnit.Case, async: false

  import Spickzettel.TestHelpers, only: [serve_fake_outline: 1]

  alias Spickzettel.FakeOutline

  @hook Path.expand("../../hooks/session-start.sh", __DIR__)
  @git_env [
    {"GIT_CONFIG_GLOBAL", "/dev/null"},
    {"GIT_CONFIG_NOSYSTEM", "1"},
    {"GIT_DIR", nil},
    {"GIT_WORK_TREE", nil}
  ]

  setup :serve_fake_outline

  setup %{base: base} do
    root = Path.join(System.tmp_dir!(), "spickzettel-hook-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(root) end)

    %{url: base <> "/mcp/test-token", root: root, repo: repository(root)}
  end

  defp repository(root) do
    main = Path.join(root, "spickzettel")
    File.mkdir_p!(main)
    git!(main, ["init", "--quiet"])

    git!(
      main,
      ["-c", "user.name=Test", "-c", "user.email=test@example.com"] ++
        ["commit", "--quiet", "--allow-empty", "--message", "Start"]
    )

    worktree = Path.join([root, "worktrees", "feature-branch"])
    git!(main, ["worktree", "add", "--quiet", "-b", "feature", worktree])
    %{main: main, worktree: worktree}
  end

  defp git!(dir, args) do
    {_output, 0} = System.cmd("git", args, cd: dir, env: @git_env, stderr_to_stdout: true)
  end

  defp run_hook(dir, url) do
    System.cmd("sh", [@hook],
      cd: dir,
      env: [{"SPICKZETTEL_URL", url} | @git_env],
      stderr_to_stdout: true
    )
  end

  test "loads the main repository's hub from a worktree", %{url: url, repo: repo} do
    assert {output, 0} = run_hook(repo.worktree, url)

    assert output =~ "# 📒 General · /memories/General\n"
    assert output =~ "# 📝 spickzettel · /memories/spickzettel\n"
    assert output =~ "- 🧪 Tests: London style · tests-london-style · 2026-10-09"
  end

  test "shortens the project hub's list over budget and points to memory view",
       %{url: url, repo: repo} do
    FakeOutline.add(
      for n <- 1..200 do
        %{
          "id" => "note-#{n}",
          "urlId" => "N#{n}",
          "title" => "Note #{n}",
          "icon" => nil,
          "parentDocumentId" => "hub-project",
          "revision" => 1,
          "text" =>
            "`name: note-#{n}` · `typ: project` · `stand: 2026-09-01`\n\n**Kurz:** " <>
              String.duplicate("A long summary. ", 6)
        }
      end
    )

    assert {output, 0} = run_hook(repo.main, url)

    assert byte_size(:unicode.characters_to_binary(output, :utf8, :utf16)) |> div(2) < 10_000
    assert output =~ "- 🇬🇧 English in repositories · english-in-repos"
    assert output =~ "- 🧪 Tests: London style"
    assert output =~ ~r/\n- … \d+ more notes: memory view \/memories\/spickzettel\n$/
  end

  test "says so when no hub matches the project", %{url: url, root: root} do
    dir = Path.join(root, "unknown")
    File.mkdir_p!(dir)

    assert {output, 0} = run_hook(dir, url)

    assert output =~ "# 📒 General · /memories/General\n"
    refute output =~ "/memories/spickzettel\n"
    assert output =~ "No hub /memories/unknown"
  end

  test "prints one line and succeeds when the server is unreachable", %{repo: repo} do
    assert {output, 0} = run_hook(repo.main, "http://127.0.0.1:1/mcp/test-token")

    assert [_line] = String.split(output, "\n", trim: true)
    assert output =~ "spickzettel"
  end
end
