defmodule Loge.Dimacs.LanguagesTest do
  use ExUnit.Case, async: true

  alias Loge.{Analysis, Diagnostic}
  alias Loge.Dimacs.{Cnf, Qdimacs, Wcnf}
  alias Loge.Dimacs.Languages

  test "describe the three languages, highlighted by one grammar" do
    for {language, id, label, extension} <- [
          {Languages.Cnf, :dimacs, "DIMACS CNF", ".cnf"},
          {Languages.Wcnf, :wcnf, "WCNF (MaxSAT)", ".wcnf"},
          {Languages.Qdimacs, :qdimacs, "QDIMACS (QBF)", ".qdimacs"}
        ] do
      assert language.id() == id
      assert language.label() == label
      assert language.extensions() == [extension]
      assert language.editor_language() == "dimacs"
      assert language.include_names("c x\n") == []
    end
  end

  test "a valid source has no diagnostics and what it states as its native analysis" do
    assert Languages.Cnf.analyze("p cnf 1 1\n1 0", []) == %Analysis{
             language: :dimacs,
             source: "p cnf 1 1\n1 0",
             diagnostics: [],
             native: %Cnf{variables: 1, clauses: [[1]]}
           }

    assert %Analysis{language: :wcnf, diagnostics: [], native: %Wcnf{}} =
             Languages.Wcnf.analyze("h 1 0\n", [])

    assert %Analysis{language: :qdimacs, diagnostics: [], native: %Qdimacs{}} =
             Languages.Qdimacs.analyze("p cnf 1 1\ne 1 0\n1 0\n", [])
  end

  test "an invalid source has its diagnostics and no native analysis" do
    assert %Analysis{diagnostics: [%Diagnostic{code: "DIMACS005"}], native: nil} =
             Languages.Cnf.analyze("p cnf 1 1\n2 0", [])

    assert %Analysis{diagnostics: [%Diagnostic{code: "DIMACS013"}], native: nil} =
             Languages.Qdimacs.analyze("p cnf 1 1\na 1 0\n1 0\n", [])
  end
end
