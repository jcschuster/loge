defmodule Loge.Shex.Languages.ShapeMapTest do
  use ExUnit.Case, async: true

  alias Loge.{Analysis, Diagnostic, Range}
  alias Loge.Shex.Languages.ShapeMap

  @roles [
    schema: Loge.source(:shex, "PREFIX sch: <http://e/>\nsch:S { sch:p . }\n"),
    data: Loge.source(:turtle, "@prefix d: <http://e/> .\nd:a d:p 1 .\n")
  ]

  test "describes shape maps" do
    assert ShapeMap.id() == :shapemap
    assert ShapeMap.label() == "ShapeMap"
    assert ShapeMap.extensions() == [".sm"]
    assert ShapeMap.editor_language() == "shapemap"
    assert ShapeMap.include_names("<http://e/a>@<http://e/S>") == []
  end

  test "with its roles, nodes are read with the data's prefixes and shapes with the schema's" do
    assert %Analysis{language: :shapemap, diagnostics: []} =
             ShapeMap.analyze("d:a@sch:S", roles: @roles)

    assert [%Diagnostic{code: "shex_error", message: message}] =
             ShapeMap.analyze("sch:a@sch:S", roles: @roles).diagnostics

    assert message =~ "Alias 'sch' not found"
  end

  test "without its roles, only its syntax is checked" do
    assert ShapeMap.analyze("d:a@sch:S", []).diagnostics == []

    assert [%Diagnostic{code: "syntax_error", range: range, message: ~s|Expected "@"|}] =
             ShapeMap.analyze("<http://e/a> <http://e/S>", []).diagnostics

    assert range == Range.new(1, column: 14, end_column: 15)
  end

  test "a role that does not read leaves the shape map unchecked" do
    roles = Keyword.put(@roles, :data, Loge.source(:turtle, "d:a d:p ."))
    assert ShapeMap.analyze("sch:a@sch:S", roles: roles).diagnostics == []
  end
end
