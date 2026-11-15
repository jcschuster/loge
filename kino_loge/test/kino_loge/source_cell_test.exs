defmodule KinoLoge.SourceCellTest do
  use ExUnit.Case, async: true

  import Kino.Test

  alias KinoLoge.SourceCell

  setup :configure_livebook_bridge

  test "a new cell binds an empty source of the first language to a fresh variable" do
    {_kino, source} = start_smart_cell!(SourceCell, %{})
    assert source =~ ~r/^source\d* = Loge.source\(:fake, ""\)$/
  end

  test "a stored variable is kept" do
    {_kino, source} = start_smart_cell!(SourceCell, %{"variable" => "defs", "source" => "fact"})
    assert source == ~s|defs = Loge.source(:fake, "fact")|
  end

  test "the client gets every language, the setup and the editor's state" do
    {kino, _source} = start_smart_cell!(SourceCell, %{"variable" => "defs", "source" => "fact"})

    assert %{
             languages: [%{id: "fake", label: "Fake"}, %{id: "other", label: "Other"}],
             language: "fake",
             editor_language: "fake",
             variable: "defs",
             source: "fact",
             version: 0,
             diagnostics: []
           } = connect(kino)
  end

  test "an edit updates the source and reaches every client" do
    {kino, _source} = start_smart_cell!(SourceCell, %{"variable" => "defs", "source" => "a"})
    updates = [%{"clientID" => "x", "changes" => [1, [0, "b"]]}]
    push_event(kino, "push", %{"version" => 0, "updates" => updates})

    assert_smart_cell_update(kino, %{"source" => "ab"}, ~s|defs = Loge.source(:fake, "ab")|)
    assert_broadcast_event(kino, "updates", ^updates)
  end

  test "the language and the variable can be changed" do
    {kino, _source} = start_smart_cell!(SourceCell, %{"variable" => "defs"})
    push_event(kino, "set_language", %{"id" => "other"})

    assert_smart_cell_update(kino, %{"language" => "other"}, ~s|defs = Loge.source(:other, "")|)
    assert_broadcast_event(kino, "setup", %{language: "other", editor_language: nil})

    push_event(kino, "set_variable", %{"name" => "axioms"})

    assert_smart_cell_update(
      kino,
      %{"variable" => "axioms"},
      ~s|axioms = Loge.source(:other, "")|
    )
  end

  test "an event it does not know changes nothing" do
    {kino, _source} = start_smart_cell!(SourceCell, %{"variable" => "defs"})
    push_event(kino, "set_variable", "not a map")
    push_event(kino, "explode", %{})

    assert connect(kino).variable == "defs"
    refute_received {:runtime_smart_cell_update, _, _, _, _}
  end

  test "includes are linted against the binding and passed in the source" do
    {kino, source} =
      start_smart_cell!(SourceCell, %{"variable" => "problem", "source" => "include defs"})

    assert source =~ ~s|includes: %{"defs" => defs}|
    assert_broadcast_event(kino, "diagnostics", [%{code: "FAKE0601"}], 1_000)

    SourceCell.scan_binding(kino.pid, [defs: Loge.source(:fake, "fact")], __ENV__)
    assert_broadcast_event(kino, "diagnostics", [], 1_000)
  end
end
