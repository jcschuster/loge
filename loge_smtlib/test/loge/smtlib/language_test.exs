defmodule Loge.Smtlib.LanguageTest do
  use ExUnit.Case, async: true

  alias Loge.{Analysis, Diagnostic}
  alias Loge.Smtlib.Language

  test "describes SMT-LIB" do
    assert Language.id() == :smtlib
    assert Language.label() == "SMT-LIB"
    assert Language.extensions() == [".smt2"]
    assert Language.editor_language() == nil
    assert Language.include_names("(check-sat)") == []
  end

  test "a clean script has no diagnostics and its terms as the native analysis" do
    assert %Analysis{language: :smtlib, diagnostics: [], native: [{:list, _, _}]} =
             Language.analyze("(check-sat)", [])
  end

  test "syntax errors, and no command checks until the script reads" do
    assert %Analysis{diagnostics: [%Diagnostic{code: "SMTLIB001"}], native: nil} =
             Language.analyze("(declare-fun f\n(check-sat)", [])
  end

  test "command findings once it reads" do
    assert %Analysis{diagnostics: [%Diagnostic{code: "SMTLIB104"}]} =
             Language.analyze("(assert)", [])
  end
end
