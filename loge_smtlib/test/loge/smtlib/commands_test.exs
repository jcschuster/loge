defmodule Loge.Smtlib.CommandsTest do
  use ExUnit.Case, async: true

  alias Loge.{Diagnostic, Range}
  alias Loge.Smtlib.{Commands, Sexp}

  defp lint(source) do
    {terms, []} = Sexp.read(source)
    Commands.lint(terms, source)
  end

  test "a well-formed script has no findings" do
    script = """
    (set-logic QF_LIA)
    (set-option :produce-models true)
    (declare-const x Int)
    (declare-fun f (Int) Int)
    (define-fun g ((y Int)) Int (+ y 1))
    (declare-sort U 0)
    (assert (! (> (f x) 2) :named a))
    (push 1)
    (check-sat)
    (get-value (x (f x)))
    (pop)
    (echo "done")
    (get-info :reason-unknown)
    (exit)
    """

    assert lint(script) == []
  end

  test "a term at the top level is not a command" do
    assert [%Diagnostic{code: "SMTLIB101", severity: :error, range: range}] =
             lint("(check-sat) x")

    assert range == Range.new(1, column: 13, end_line: 1, end_column: 14)
  end

  test "a command needs a name" do
    assert [%Diagnostic{code: "SMTLIB102"}] = lint("()")
    assert [%Diagnostic{code: "SMTLIB102"}] = lint("((check-sat))")
  end

  test "a name outside SMT-LIB 2.6 is a warning, since solvers extend the language" do
    assert [%Diagnostic{code: "SMTLIB103", severity: :warning, message: message, range: range}] =
             lint("(simplify (+ 1 2))")

    assert message =~ "`simplify`"
    assert range == Range.new(1, column: 2, end_line: 1, end_column: 10)
  end

  test "the number of arguments is checked, on the command" do
    assert [%Diagnostic{code: "SMTLIB104", message: message, range: range}] =
             lint("(check-sat)\n(declare-const x)")

    assert message == "`declare-const` takes a symbol and a sort."
    assert range == Range.new(2, column: 1, end_line: 2, end_column: 18)

    assert [%Diagnostic{code: "SMTLIB104", message: "`check-sat` takes no arguments."}] =
             lint("(check-sat x)")

    assert [%Diagnostic{message: "`push` takes an optional numeral."}] = lint("(push 1 2)")
  end

  test "an argument of the wrong kind is reported on the argument" do
    assert [%Diagnostic{code: "SMTLIB105", message: message, range: range}] =
             lint("(declare-fun 1 () Int)")

    assert message == "Expected a symbol."
    assert range == Range.new(1, column: 14, end_line: 1, end_column: 15)

    assert [%Diagnostic{message: "Expected a list."}] = lint("(declare-fun f Int Int)")

    assert [%Diagnostic{message: "Expected a keyword."}] =
             lint("(set-option produce-models true)")

    assert [%Diagnostic{message: "Expected a string."}] = lint("(echo hi)")
  end

  test "counts the check-sat commands" do
    {terms, []} = Sexp.read("(check-sat)(push)(check-sat-assuming (p))(check-sat)")
    assert Commands.count(terms, ["check-sat", "check-sat-assuming"]) == 3
  end
end
