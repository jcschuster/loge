defmodule Loge.Asp.LanguageTest do
  use ExUnit.Case, async: true

  alias Loge.{Analysis, Diagnostic, Range}
  alias Loge.Asp.Language

  test "describes ASP" do
    assert Language.id() == :asp
    assert Language.label() == "ASP"
    assert Language.extensions() == [".lp"]
    assert Language.editor_language() == nil
    assert Language.include_names("#include \"a.lp\".") == []
  end

  test "a clean program has no diagnostics" do
    assert Language.analyze("a. b :- a.", []) ==
             %Analysis{language: :asp, source: "a. b :- a.", diagnostics: [], native: nil}
  end

  test "grounding reports undefined atoms" do
    assert %Analysis{
             diagnostics: [%Diagnostic{code: "atom-undefined", severity: :info} = undefined]
           } =
             Language.analyze("a :- b.", [])

    assert undefined.range == Range.new(1, column: 6, end_line: 1, end_column: 7)
  end

  test "grounding reports unsafe variables" do
    assert %Analysis{diagnostics: [%Diagnostic{code: "error", severity: :error} = unsafe]} =
             Language.analyze("a.\np(X) :- a.", [])

    assert unsafe.range.line == 2
    assert [{%Range{line: 2, column: 3}, "'X' is unsafe"}] = unsafe.related
  end

  test "a syntax error" do
    assert %Analysis{diagnostics: [%Diagnostic{severity: :error, range: %Range{line: 2}}]} =
             Language.analyze("a.\nb :- c d.", [])
  end

  test "grounding that does not end is cut off" do
    {microseconds, %Analysis{diagnostics: []}} =
      :timer.tc(fn -> Language.analyze("p(0). p(X+1) :- p(X).", []) end)

    assert microseconds in 10_000_000..12_000_000
  end

  test "the analysis does not search for models" do
    pigeons = "p(1..12). h(1..11). 1 {at(P,H) : h(H)} 1 :- p(P). :- at(P,H), at(Q,H), P < Q."

    {microseconds, %Analysis{diagnostics: []}} =
      :timer.tc(fn -> Language.analyze(pigeons, []) end)

    assert microseconds < 2_000_000
  end
end
