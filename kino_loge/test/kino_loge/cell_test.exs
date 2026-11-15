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

    assert data.languages == [%{id: "fake", label: "Fake"}]

    assert data.engines == [
             %{id: "fake_engine", label: "Fake engine", group: "Solve"},
             %{id: "second_engine", label: "Second engine", group: "Solve"},
             %{id: "validator", label: "Validator", group: "Check"},
             %{id: "translator", label: "Translator → Other", group: "Translate"}
           ]

    assert data.language == "fake"
    assert data.engine == "fake_engine"

    assert %{key: "system", type: "select", choices: ["A", "B"], value: "A"} =
             Enum.find(data.controls, &(&1.key == "system"))

    assert %{key: "limit", type: "integer", value: 9} =
             Enum.find(data.controls, &(&1.key == "limit"))

    assert %{key: "mode", choices: ["fast", "slow"], value: "fast"} =
             Enum.find(data.controls, &(&1.key == "mode"))

    assert data.inputs == [%{id: "", label: "This cell's editor"}]
    assert data.input == nil
    assert data.roles == []
    assert data.variable == ""
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

  test "another engine changes the controls" do
    {kino, _source} = start_smart_cell!(Cell, %{})
    push_event(kino, "set_engine", %{"id" => "translator"})

    assert_smart_cell_update(kino, %{"engine" => "translator"}, source)
    assert source =~ "Loge.run!(KinoLoge.Fake.Translator"
    assert_broadcast_event(kino, "setup", %{engine: "translator", controls: []})
  end

  test "a control change updates the source and every client" do
    {kino, _source} = start_smart_cell!(Cell, %{})
    push_event(kino, "set_option", %{"key" => "limit", "value" => "30"})

    assert_smart_cell_update(kino, %{"options" => %{"limit" => 30}}, source)
    assert source =~ "limit: 30"
    assert_broadcast_event(kino, "setup", %{engine: "fake_engine"})
  end

  test "the outcome is bound to the result name" do
    {kino, _source} = start_smart_cell!(Cell, %{"engine" => "translator", "source" => "p"})
    push_event(kino, "set_variable", %{"name" => "cnf"})

    assert_smart_cell_update(
      kino,
      %{"variable" => "cnf"},
      ~s|cnf = Loge.run!(KinoLoge.Fake.Translator, "p", [])|
    )
  end

  test "the bound inputs of the cell's language are offered as its input" do
    {kino, _source} = start_smart_cell!(Cell, %{})

    Cell.scan_binding(
      kino.pid,
      [
        problem: Loge.source(:fake, "p"),
        cnf: %Loge.Outcome{
          status: :equivalent,
          raw: "",
          engine: :e,
          output: Loge.source(:fake, "c")
        },
        log: %Loge.Outcome{status: :success, raw: "", engine: :e},
        other: Loge.source(:other, "x")
      ],
      __ENV__
    )

    assert_broadcast_event(kino, "setup", %{inputs: inputs})

    assert Enum.sort(inputs) == [
             %{id: "", label: "This cell's editor"},
             %{id: "cnf", label: "cnf"},
             %{id: "problem", label: "problem"}
           ]
  end

  test "a bound input is run and shown in place of the editor's source" do
    {kino, _source} = start_smart_cell!(Cell, %{"source" => "unused"})
    Cell.scan_binding(kino.pid, [problem: Loge.source(:fake, "p")], __ENV__)
    assert_broadcast_event(kino, "setup", %{inputs: [_, _]})
    push_event(kino, "set_input", %{"name" => "problem"})

    assert_smart_cell_update(kino, %{"input" => "problem"}, source)
    assert source =~ "Loge.run!(KinoLoge.Fake.Engine, problem,"
    assert %{input: "problem", input_text: "p"} = connect(kino)

    push_event(kino, "set_input", %{"name" => nil})
    assert_smart_cell_update(kino, %{"input" => nil}, source)
    assert source =~ ~s|"unused"|
  end

  test "an input no longer bound stays chosen and says so" do
    {kino, _source} = start_smart_cell!(Cell, %{"input" => "gone"})

    assert %{input: "gone", input_text: nil, inputs: [_editor, %{id: "gone", label: label}]} =
             connect(kino)

    assert label =~ "not bound"
  end

  test "each role offers the bound inputs of its languages" do
    {kino, _source} = start_smart_cell!(Cell, %{"engine" => "validator"})

    assert [
             %{key: "data", label: "Data", required: true, choices: [none], value: nil},
             %{key: "schema", required: false}
           ] = connect(kino).roles

    assert none == %{id: "", label: "none"}

    bound = [
      graph: Loge.source(:other, "g"),
      shapes: Loge.source(:fake, "s"),
      log: %Loge.Outcome{status: :success, raw: "", engine: :e}
    ]

    Cell.scan_binding(kino.pid, bound, __ENV__)
    assert_broadcast_event(kino, "setup", %{roles: [data, schema]})

    assert data.choices == [none, %{id: "graph", label: "graph"}]
    assert schema.choices == [none, %{id: "shapes", label: "shapes"}]
  end

  test "a chosen role is passed its variable, and one no longer bound says so" do
    {kino, _source} = start_smart_cell!(Cell, %{"engine" => "validator"})
    push_event(kino, "set_role", %{"key" => "data", "name" => "graph"})

    assert_smart_cell_update(kino, %{"roles" => %{"data" => "graph"}}, source)
    assert source == ~s|Loge.run!(KinoLoge.Fake.Validator, "", data: graph)|

    assert %{roles: [%{value: "graph", choices: [_none, %{id: "graph", label: label}]}, _schema]} =
             connect(kino)

    assert label =~ "not bound"

    push_event(kino, "set_role", %{"key" => "data", "name" => nil})
    assert_smart_cell_update(kino, %{"roles" => %{"data" => nil}}, source)
    assert source == ~s|Loge.run!(KinoLoge.Fake.Validator, "", [])|
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
