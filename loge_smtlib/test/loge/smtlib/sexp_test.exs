defmodule Loge.Smtlib.SexpTest do
  use ExUnit.Case, async: true

  alias Loge.{Diagnostic, Range}
  alias Loge.Smtlib.Sexp

  doctest Sexp

  defp codes(source) do
    {_terms, diagnostics} = Sexp.read(source)
    Enum.map(diagnostics, &{&1.code, &1.range})
  end

  test "reads lists and the atoms of SMT-LIB 2.6 with their byte spans" do
    source = ~S{(assert (= x #x1F #b10 1.5 0 "a ""b""" |two words| :named))}

    assert {[{:list, [assert, {:list, items, _}], {0, 59}}], []} = Sexp.read(source)
    assert assert == {:symbol, "assert", {1, 6}}

    assert Enum.map(items, &Tuple.delete_at(&1, 2)) == [
             {:symbol, "="},
             {:symbol, "x"},
             {:hexadecimal, "#x1F"},
             {:binary, "#b10"},
             {:decimal, "1.5"},
             {:numeral, "0"},
             {:string, "a \"b\""},
             {:symbol, "two words"},
             {:keyword, ":named"}
           ]
  end

  test "skips comments and whitespace" do
    assert {[{:symbol, "a", {12, 1}}, {:symbol, "b", {19, 1}}], []} =
             Sexp.read("; (comment\n a ; x\n\tb")
  end

  test "symbols may hold the characters SMT-LIB allows" do
    assert {[{:symbol, "a.b~!@$%^&*_-+=<>?/", _}], []} = Sexp.read("a.b~!@$%^&*_-+=<>?/")
  end

  test "an unclosed list is reported on its parenthesis, and its items are kept" do
    assert {[{:list, [{:symbol, "assert", _}, {:symbol, "x", _}], {0, 10}}], diagnostics} =
             Sexp.read("(assert x\n")

    assert [%Diagnostic{code: "SMTLIB001", severity: :error, range: range}] = diagnostics
    assert range == Range.new(1, column: 1, end_line: 1, end_column: 2)
  end

  test "an unmatched closing parenthesis" do
    assert codes("(a))") == [{"SMTLIB002", Range.new(1, column: 4, end_line: 1, end_column: 5)}]
  end

  test "an unterminated string or quoted symbol runs to the end" do
    assert codes(~S|(echo "abc)|) == [
             {"SMTLIB001", Range.new(1, column: 1, end_line: 1, end_column: 2)},
             {"SMTLIB003", Range.new(1, column: 7, end_line: 1, end_column: 12)}
           ]

    assert [{"SMTLIB001", _}, {"SMTLIB004", range}] = codes("(a |b")
    assert range == Range.new(1, column: 4, end_line: 1, end_column: 6)
  end

  test "a token that is no SMT-LIB atom" do
    assert codes("(a #z1 01 1.)") == [
             {"SMTLIB005", Range.new(1, column: 4, end_line: 1, end_column: 7)},
             {"SMTLIB005", Range.new(1, column: 8, end_line: 1, end_column: 10)},
             {"SMTLIB005", Range.new(1, column: 11, end_line: 1, end_column: 13)}
           ]
  end

  test "spans count bytes; ranges count UTF-16 columns" do
    assert {[{:string, "é😀", {0, 8}}, {:symbol, "x", {9, 1}}], []} = Sexp.read(~S|"é😀" x|)

    assert codes(~S|"é😀" )|) == [
             {"SMTLIB002", Range.new(1, column: 7, end_line: 1, end_column: 8)}
           ]
  end
end
