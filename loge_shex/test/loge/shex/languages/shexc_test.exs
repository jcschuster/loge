defmodule Loge.Shex.Languages.ShexcTest do
  use ExUnit.Case, async: true

  alias Loge.{Analysis, Diagnostic, Range}
  alias Loge.Shex.Languages.Shexc

  test "describes ShExC" do
    assert Shexc.id() == :shex
    assert Shexc.label() == "ShExC"
    assert Shexc.extensions() == [".shex"]
    assert Shexc.editor_language() == "shex"
    assert Shexc.include_names("IMPORT <http://e/defs>") == []
  end

  test "a schema that reads has no diagnostics" do
    assert %Analysis{language: :shex, diagnostics: [], native: nil} =
             Shexc.analyze("PREFIX : <http://e/>\n:S { :p . }\n", [])
  end

  test "a syntax error, positioned on the source" do
    assert [%Diagnostic{code: "syntax_error", range: range, message: message}] =
             Shexc.analyze("PREFIX : <http://e/>\n:S { :p . ;\n  :q \"é😀\" ] }\n", []).diagnostics

    assert range == Range.new(2, column: 4, end_column: 5)
    assert message == "Expected shape expression definition or external"
  end

  test "a reference to a shape the schema does not have" do
    assert [%Diagnostic{code: "shex_error", message: message}] =
             Shexc.analyze("PREFIX : <http://e/>\n:S { :p @:T }\n", []).diagnostics

    assert message =~ "Shape label not found http://e/T"
  end
end
