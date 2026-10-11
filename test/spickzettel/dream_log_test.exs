defmodule Spickzettel.DreamLogTest do
  use ExUnit.Case, async: true

  import Mox

  import Spickzettel.TestHelpers, only: [applied: 2]

  alias Spickzettel.{Document, DreamLog, Edit, IndexMock, OutlineMock}

  setup :verify_on_exit!

  @deps %{
    index: IndexMock,
    outline: OutlineMock,
    dream_log: {:note, "General", "dream-log"},
    dream_log_archive: {:note, "General", "dream-log-archive"}
  }

  defp run(date, size), do: "## #{date} · Dream\n\n" <> String.duplicate("x", size) <> "\n"

  defp patched(document, patch),
    do: %{document | text: Edit.apply(document.text, patch), revision: document.revision + 1}

  defp log(sizes) do
    runs = for {size, day} <- Enum.with_index(sizes), do: run("2026-10-#{20 - day}", size)
    Enum.join(["Log of all runs, newest first.\n" | runs], "\n")
  end

  describe "overflow" do
    test "cuts the fewest oldest sections that bring the log below the limit" do
      text = log([6_000, 5_000, 4_000, 3_000])

      assert {:ok, cut, sections, 2} = DreamLog.overflow(text)
      assert sections == String.trim(run("2026-10-18", 4_000) <> "\n" <> run("2026-10-17", 3_000))
      assert cut == "\n\n" <> sections
      assert String.replace(text, cut, "") == log([6_000, 5_000])
    end

    test "keeps the newest section even when it alone is too long" do
      assert {:ok, _cut, _sections, 2} = DreamLog.overflow(log([16_000, 10, 10]))
    end

    test "leaves logs alone that are short enough or have only one section" do
      assert DreamLog.overflow(log([6_000, 5_000])) == :none
      assert DreamLog.overflow(log([16_000])) == :none
    end
  end

  describe "prepend" do
    test "puts the sections before the archive's first section" do
      archive = "Older runs, newest first.\n\n## 2026-10-01 · Dream\n\nOld.\n"

      assert applied(archive, DreamLog.prepend(archive, "## 2026-10-02 · Dream\n\nNew.")) ==
               "Older runs, newest first.\n\n## 2026-10-02 · Dream\n\nNew.\n\n" <>
                 "## 2026-10-01 · Dream\n\nOld.\n"
    end

    test "appends them to an archive without sections" do
      assert applied("Older runs.\n", DreamLog.prepend("Older runs.\n", "## A\n\nNew.")) ==
               "Older runs.\n\n## A\n\nNew.\n"
    end
  end

  describe "archive" do
    setup do
      text = log([8_000, 4_000, 3_000, 1_000])
      dream_log = %Document{id: "log", title: "Dream log", revision: 5, text: text}
      archive = %Document{id: "archive", title: "Archive", revision: 2, text: "Older runs.\n"}

      stub(IndexMock, :lookup, fn "General", "dream-log-archive" -> {:ok, archive} end)

      stub(OutlineMock, :get_document, fn
        "log" -> {:ok, dream_log}
        "archive" -> {:ok, archive}
      end)

      %{dream_log: dream_log, archive: archive}
    end

    test "moves the oldest sections from the dream log into the archive", context do
      expect(OutlineMock, :patch_document, fn "archive", patch, 2 ->
        assert Edit.apply(context.archive.text, patch) =~ "Older runs.\n\n## 2026-10-18"
        {:ok, patched(context.archive, patch)}
      end)

      expect(OutlineMock, :patch_document, fn "log", patch, 5 ->
        assert Edit.apply(context.dream_log.text, patch) == log([8_000, 4_000])
        {:ok, patched(context.dream_log, patch)}
      end)

      assert DreamLog.archive(@deps.dream_log, context.dream_log, @deps) == [
               "Moved the 2 oldest sections of the dream log to /memories/General/dream-log-archive."
             ]
    end

    test "warns when the sections could not leave the dream log", context do
      expect(OutlineMock, :patch_document, fn "archive", patch, 2 ->
        {:ok, patched(context.archive, patch)}
      end)

      expect(OutlineMock, :patch_document, fn "log", _patch, 5 -> {:error, {:status, 500}} end)

      assert DreamLog.archive(@deps.dream_log, context.dream_log, @deps) == [
               "Warning: copied the 2 oldest sections to /memories/General/dream-log-archive, " <>
                 "but could not remove them from the dream log: Outline answered with status 500."
             ]
    end

    test "warns and leaves the dream log alone when the archive is missing", context do
      expect(IndexMock, :lookup, fn "General", "dream-log-archive" -> {:error, :not_found} end)

      assert [
               "Warning: the dream log was not archived: " <>
                 "No note at /memories/General/dream-log-archive." <> _
             ] = DreamLog.archive(@deps.dream_log, context.dream_log, @deps)
    end

    test "ignores other notes and short dream logs", context do
      assert DreamLog.archive({:note, "General", "other"}, context.dream_log, @deps) == []
      short = %{context.dream_log | text: log([10])}
      assert DreamLog.archive(@deps.dream_log, short, @deps) == []
    end
  end
end
