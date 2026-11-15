defmodule Loge.Turtle.LanguageTest do
  use ExUnit.Case, async: true

  alias Loge.{Analysis, Diagnostic, Range}
  alias Loge.Turtle.Language

  test "describes Turtle" do
    assert Language.id() == :turtle
    assert Language.label() == "Turtle"
    assert Language.extensions() == [".ttl"]
    assert Language.editor_language() == "turtle"
    assert Language.include_names("@prefix : <http://e/> .") == []
  end

  test "a graph that reads has no diagnostics" do
    assert %Analysis{language: :turtle, diagnostics: [], native: nil} =
             Language.analyze("@prefix : <http://e/> .\n:a :p 1 .\n", [])
  end

  test "the first error, positioned on the source" do
    source = "@prefix : <http://e/> .\n:a :p \"é😀\" :c :d .\n:e :p :f :g .\n"

    assert [%Diagnostic{code: "syntax_error", severity: :error, range: range, message: message}] =
             Language.analyze(source, []).diagnostics

    assert range == Range.new(2, column: 13, end_column: 15)
    assert message == "A dot is expected at the end of statements"
  end

  test "an undeclared prefix" do
    assert [%Diagnostic{range: range, message: message}] =
             Language.analyze("@prefix : <http://e/> .\n:a ex:p 1 .\n", []).diagnostics

    assert range == Range.new(2, column: 4, end_column: 8)
    assert message == "The prefix ex: has not been declared"
  end
end
