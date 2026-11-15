defmodule Loge.Sparql.LanguageTest do
  use ExUnit.Case, async: true

  alias Loge.{Analysis, Diagnostic, Range}
  alias Loge.Sparql.Language

  test "describes SPARQL" do
    assert Language.id() == :sparql
    assert Language.label() == "SPARQL"
    assert Language.extensions() == [".rq"]
    assert Language.editor_language() == "sparql"
    assert Language.include_names("SELECT * { ?s ?p ?o }") == []
  end

  test "a query that reads has no diagnostics" do
    assert %Analysis{language: :sparql, diagnostics: [], native: nil} =
             Language.analyze("PREFIX : <http://e/>\nSELECT ?x WHERE { ?x :p ?y }", [])
  end

  test "the point where the reader stopped, one character, in UTF-16 columns" do
    source = "PREFIX : <http://e/>\nSELECT * WHERE { ?x :p \"😀\" . ?x ?y }"

    assert [%Diagnostic{code: "syntax_error", severity: :error, range: range, message: message}] =
             Language.analyze(source, []).diagnostics

    assert range == Range.new(2, column: 38, end_column: 39)
    assert message =~ "expected"
  end
end
