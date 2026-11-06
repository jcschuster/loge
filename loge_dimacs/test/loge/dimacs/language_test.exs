defmodule Loge.Dimacs.LanguageTest do
  use ExUnit.Case, async: true

  alias Loge.{Analysis, Diagnostic}
  alias Loge.Dimacs.{Cnf, Language}

  test "describes DIMACS CNF" do
    assert Language.id() == :dimacs
    assert Language.label() == "DIMACS CNF"
    assert Language.extensions() == [".cnf"]
    assert Language.editor_language() == nil
    assert Language.include_names("p cnf 1 1\n1 0") == []
  end

  test "a valid source has no diagnostics and the formula as its native analysis" do
    assert Language.analyze("p cnf 1 1\n1 0", []) == %Analysis{
             language: :dimacs,
             source: "p cnf 1 1\n1 0",
             diagnostics: [],
             native: %Cnf{variables: 1, clauses: [[1]]}
           }
  end

  test "an invalid source has its diagnostics and no formula" do
    assert %Analysis{diagnostics: [%Diagnostic{code: "DIMACS005"}], native: nil} =
             Language.analyze("p cnf 1 1\n2 0", [])
  end
end
