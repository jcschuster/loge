defmodule Loge.Egglog.LanguageTest do
  use ExUnit.Case, async: true

  alias Loge.{Analysis, Diagnostic, Range}
  alias Loge.Egglog.Language

  test "describes egglog" do
    assert Language.id() == :egglog
    assert Language.label() == "egglog"
    assert Language.extensions() == [".egg"]
    assert Language.editor_language() == nil
    assert Language.include_names("(include \"defs.egg\")") == []
  end

  test "a program that parses has no diagnostics" do
    assert %Analysis{language: :egglog, diagnostics: [], native: nil} =
             Language.analyze("(datatype M (Num i64))\n(let x (Num 1))", [])
  end

  test "a parse error is placed by its byte range, in UTF-16 columns" do
    assert %Analysis{diagnostics: [diagnostic]} = Language.analyze("; é😀\n(let x (Num 1) ))", [])

    assert diagnostic ==
             Diagnostic.new(
               "parse_error",
               :error,
               Range.new(2, column: 17, end_line: 2, end_column: 18),
               "parse error: unexpected `)`"
             )
  end

  test "an error at the end of the source has an empty range there" do
    assert %Analysis{diagnostics: [%Diagnostic{range: range}]} =
             Language.analyze("(datatype M\n (Num i64)", [])

    assert range == Range.new(2, column: 11, end_line: 2, end_column: 11)
  end

  test "the analysis does not run the program" do
    endless =
      "(datatype E (Num i64) (Add E E))\n(rule ((= x (Add a b)) (= y (Add c d))) ((Add x y)))\n(let e (Add (Num 1) (Num 2)))\n(run 100)"

    {microseconds, %Analysis{diagnostics: []}} =
      :timer.tc(fn -> Language.analyze(endless, []) end)

    assert microseconds < 1_000_000
  end
end
