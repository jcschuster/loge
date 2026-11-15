defmodule Loge.Prolog.LanguageTest do
  use ExUnit.Case, async: true

  alias Loge.{Analysis, Diagnostic, Range}
  alias Loge.Prolog.Language

  doctest Loge.Prolog.Includes

  defp diagnostics(source), do: Language.analyze(source, []).diagnostics

  test "describes Prolog" do
    assert Language.id() == :prolog
    assert Language.label() == "Prolog"
    assert Language.extensions() == [".pl", ".pro"]
    assert Language.editor_language() == "prolog"
  end

  test "a source names what it includes in its directives, by atoms" do
    source = """
    :- [defs, library(lists), 'my defs'].
    :- include(facts).
    :- consult(more).% a comment after the full stop
    :- ensure_loaded(rules).
    p :- [not_a_directive].
    :- initialization(main).
    """

    assert Language.include_names(source) == ["defs", "my defs", "facts", "more", "rules"]
  end

  test "names in comments, strings and quoted atoms are not includes" do
    source = """
    % :- [commented].
    /* :- [blocked]. */
    p("\\":- [quoted].").
    q(0'., ':- [atom].').
    :- [real].
    """

    assert Language.include_names(source) == ["real"]
  end

  test "a clean program has no diagnostics" do
    assert %Analysis{language: :prolog, diagnostics: [], native: nil} =
             Language.analyze("p(a).\nq(X) :- p(X).", [])
  end

  test "a singleton variable is a warning on the variable" do
    assert [%Diagnostic{code: "singleton", severity: :warning, range: range, message: message}] =
             diagnostics("% é😀\nq(X, Y) :- p(Y).")

    assert range == Range.new(2, column: 3, end_line: 2, end_column: 4)
    assert message == "Singleton variable X"
  end

  test "a query's variables are what it asks for, not singletons" do
    assert diagnostics("p(a).\n?- p(X).") == []
  end

  test "variables starting with an underscore may occur once" do
    assert diagnostics("q(_X, _) :- true.") == []
  end

  test "singletons inside lists, braces and parentheses" do
    assert ["H", "T", "Z", "C"] ==
             "ok([H|T], {Z}) :- (C)."
             |> diagnostics()
             |> Enum.map(&String.replace_prefix(&1.message, "Singleton variable ", ""))
  end

  test "a syntax error, and the clauses after it are still read" do
    assert [
             %Diagnostic{code: "syntax_error", severity: :error, range: %Range{line: 1}},
             singleton
           ] =
             diagnostics("broken( :- x.\nq(X) :- true.")

    assert singleton.range.line == 2
  end

  test "an unterminated last clause" do
    assert [%Diagnostic{code: "syntax_error", message: message}] = diagnostics("p(a).\nq(b")
    assert message =~ "end of file"
  end

  test "operators the program declares apply to the clauses after them" do
    assert diagnostics(":- op(700, xfx, ===>).\na ===> b.") == []
  end

  test "CRLF line ends" do
    assert [%Diagnostic{range: range}] = diagnostics("p(a).\r\nq(X) :- true.\r\n")
    assert range == Range.new(2, column: 3, end_line: 2, end_column: 4)
  end
end
