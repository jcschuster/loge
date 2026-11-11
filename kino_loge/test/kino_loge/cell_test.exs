defmodule KinoLoge.CellTest do
  use ExUnit.Case, async: true

  import Kino.Test

  alias KinoLoge.Cell

  setup :configure_livebook_bridge

  test "a new cell runs the first engine of the first language" do
    {_kino, source} = start_smart_cell!(Cell, %{})
    assert source =~ ~s|Loge.run!(KinoLoge.Fake.Engine, ""|
  end

  test "the client gets the choices and the current setup" do
    {kino, _source} = start_smart_cell!(Cell, %{"options" => %{"limit" => 9}})
    data = connect(kino)

    assert data.languages == [%{id: "fake", label: "Fake"}, %{id: "other", label: "Other"}]

    assert data.engines == [
             %{id: "fake_engine", label: "Fake engine"},
             %{id: "second_engine", label: "Second engine"}
           ]

    assert data.language == "fake"
    assert data.engine == "fake_engine"

    assert %{key: "system", type: "select", choices: ["A", "B"], value: "A"} =
             Enum.find(data.controls, &(&1.key == "system"))

    assert %{key: "limit", type: "integer", value: 9} =
             Enum.find(data.controls, &(&1.key == "limit"))

    assert %{key: "mode", choices: ["fast", "slow"], value: "fast"} =
             Enum.find(data.controls, &(&1.key == "mode"))

    assert data.diagnostics == []
  end

  test "the client gets the source, its version and the name of its grammar" do
    {kino, _source} = start_smart_cell!(Cell, %{"source" => "fact"})

    assert %{source: "fact", version: 0, editor_language: "fake"} = connect(kino)
  end

  test "an edit updates the source and reaches every client" do
    {kino, _source} = start_smart_cell!(Cell, %{"source" => "query"})
    updates = [edit("a", [5, [0, "!"]]), edit("a", [[1, "Q"], 5])]
    push_event(kino, "push", %{"version" => 0, "updates" => updates})

    assert_smart_cell_update(kino, %{"source" => "Query!"}, source)
    assert source =~ ~s|"Query!"|
    assert_broadcast_event(kino, "updates", ^updates)
    assert %{source: "Query!", version: 2} = connect(kino)
  end

  test "an edit made against another version is left to its client to rebase" do
    {kino, _source} = start_smart_cell!(Cell, %{"source" => "query"})
    push_event(kino, "push", %{"version" => 0, "updates" => [edit("a", [5, [0, "!"]])]})
    push_event(kino, "push", %{"version" => 0, "updates" => [edit("b", [5, [0, "?"]])]})
    push_event(kino, "push", %{"version" => 1, "updates" => [edit("b", [6, [0, "?"]])]})

    assert_broadcast_event(kino, "updates", [%{"clientID" => "a"}])
    assert_broadcast_event(kino, "updates", [%{"clientID" => "b", "changes" => [6, [0, "?"]]}])
    assert %{source: "query!?", version: 2} = connect(kino)
  end

  test "an edit that does not fit the source changes nothing" do
    {kino, _source} = start_smart_cell!(Cell, %{"source" => "query"})
    updates = [edit("a", [5, [0, "!"]]), edit("a", [9])]
    push_event(kino, "push", %{"version" => 0, "updates" => updates})

    assert %{source: "query", version: 0} = connect(kino)
    refute_received {:runtime_smart_cell_update, _, _, _, _}
  end

  test "another language changes the grammar" do
    {kino, _source} = start_smart_cell!(Cell, %{})
    push_event(kino, "set_language", %{"id" => "other"})

    assert_broadcast_event(kino, "setup", %{language: "other", editor_language: nil})
  end

  test "a control change updates the source and every client" do
    {kino, _source} = start_smart_cell!(Cell, %{})
    push_event(kino, "set_option", %{"key" => "limit", "value" => "30"})

    assert_smart_cell_update(kino, %{"options" => %{"limit" => 30}}, source)
    assert source =~ "limit: 30"
    assert_broadcast_event(kino, "setup", %{engine: "fake_engine"})
  end

  test "no engine makes a definitions cell bound to a variable" do
    {kino, _source} = start_smart_cell!(Cell, %{"source" => "fact"})
    push_event(kino, "set_engine", %{"id" => nil})
    push_event(kino, "set_variable", %{"name" => "defs"})

    assert_smart_cell_update(
      kino,
      %{"engine" => nil, "variable" => "defs"},
      ~s|defs = Loge.source(:fake, "fact")|
    )
  end

  test "an event it does not know changes nothing" do
    {kino, source} = start_smart_cell!(Cell, %{})
    push_event(kino, "set_option", "not a map")
    push_event(kino, "explode", %{})

    assert connect(kino).engine == "fake_engine"
    refute_received {:runtime_smart_cell_update, _, _, _, _}
    assert source =~ "Loge.run!"
  end

  test "an edit is linted, positions in the editor's format" do
    {kino, _source} = start_smart_cell!(Cell, %{})
    push_event(kino, "push", %{"version" => 0, "updates" => [edit("a", [[0, "include defs"]])]})

    assert_broadcast_event(
      kino,
      "diagnostics",
      [
        %{line: 1, severity: :error, description: "cannot include defs", code: "FAKE0601"}
      ],
      1_000
    )
  end

  test "an include resolves against the cell's binding" do
    {kino, _source} = start_smart_cell!(Cell, %{"source" => "include defs"})
    assert_broadcast_event(kino, "diagnostics", [%{code: "FAKE0601"}], 1_000)

    Cell.scan_binding(
      kino.pid,
      [defs: Loge.source(:fake, "fact"), other: Loge.source(:other, "x"), n: 1],
      __ENV__
    )

    assert_broadcast_event(kino, "diagnostics", [], 1_000)
  end

  defp edit(client, changes), do: %{"clientID" => client, "changes" => changes}
end
