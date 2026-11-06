defmodule Loge.Smtlib.SolverTest do
  use ExUnit.Case, async: true

  alias Loge.{Diagnostic, Outcome, Range}
  alias Loge.Smtlib.Engines.Z3

  @fake Path.expand("../../fixtures/fake_solver", __DIR__)

  defp run(script, options \\ []), do: Z3.run(script, [executable: @fake] ++ options)

  test "one check-sat gives the SZS status" do
    for {answer, szs} <- [sat: :satisfiable, unsat: :unsatisfiable, unknown: :unknown] do
      assert {:ok, %Outcome{szs: ^szs, engine: :z3, raw: raw}} =
               run("(check-sat)\n;> #{answer}\n")

      assert raw == "#{answer}\n"
    end
  end

  test "a model is a table of its definitions, as the solver wrote them" do
    script = """
    (declare-const x Int)
    (declare-const s String)
    (check-sat)
    (get-model)
    ;> sat
    ;> (
    ;>   (define-fun x () Int
    ;>     (- 3))
    ;>   (define-fun s () String "a b")
    ;> )
    """

    assert {:ok, %Outcome{szs: :satisfiable, views: [model]}} = run(script)

    assert model ==
             {:table, ["Name", "Sort", "Value"],
              [["x", "Int", "(- 3)"], ["s", "String", ~S|"a b"|]]}
  end

  test "functions in a model show their arguments" do
    script = """
    (check-sat)
    ;> sat
    ;> ((define-fun f ((x!0 Int)) Bool true))
    """

    assert {:ok, %Outcome{views: [{:table, ["Name", "Arguments", "Sort", "Value"], [row]}]}} =
             run(script)

    assert row == ["f", "((x!0 Int))", "Bool", "true"]
  end

  test "several check-sats are a table of results, without an SZS status" do
    script = "(check-sat)(push)(check-sat-assuming (p))(check-sat)\n;> sat\n;> unsat\n;> sat\n"

    assert {:ok, %Outcome{szs: nil, views: [table]}} = run(script)

    assert table ==
             {:table, ["check-sat", "Result"], [["1", "sat"], ["2", "unsat"], ["3", "sat"]]}
  end

  test "solver errors are diagnostics on the script, beside the results" do
    script = """
    (declare-const x Int)
    (assert (> y 1))
    (check-sat)
    ;> (error "line 2 column 11: unknown constant y")
    ;> sat
    """

    assert {:ok, %Outcome{szs: :satisfiable, views: [{:diagnostics, [diagnostic]}]}} = run(script)

    assert diagnostic ==
             Diagnostic.new(
               "solver",
               :error,
               Range.new(2, column: 12, end_line: 2, end_column: 13),
               "unknown constant y"
             )
  end

  test "cvc5's error positions and errors without positions" do
    script = """
    (check-sat)
    ;> (error "Parse Error: /tmp/loge_1.smt2:1.2: Expected RPAREN_TOK")
    ;> (error "cannot push when not solving incrementally")
    """

    assert {:ok, %Outcome{szs: nil, views: [{:diagnostics, [positioned, general]}]}} = run(script)
    assert positioned.range == Range.new(1, column: 2, end_line: 1, end_column: 11)
    assert positioned.message == "Expected RPAREN_TOK"
    assert general.range == Range.new(1)
  end

  test "past the time limit the run is a timeout, keeping the results so far" do
    script = "(check-sat)\n(check-sat)\n;> sat\n;hang\n"

    assert {:ok, %Outcome{szs: nil, views: [table]}} = run(script, time_limit: 1)
    assert table == {:table, ["check-sat", "Result"], [["1", "sat"], ["2", "timeout"]]}

    assert {:ok, %Outcome{szs: :timeout, views: []}} = run("(check-sat)\n;hang\n", time_limit: 1)
  end

  test "a script that does not read is an error carrying its diagnostics" do
    assert {:error, {:invalid_script, [%Diagnostic{code: "SMTLIB001"}]} = reason} =
             run("(check-sat")

    assert Z3.format_error(reason) =~ ~r/^Invalid SMT-LIB script:\nline 1: Unclosed/
  end

  test "command warnings do not stop the run" do
    assert {:ok, %Outcome{szs: :satisfiable}} = run("(simplify x)\n(check-sat)\n;> sat\n")
  end

  test "a missing executable is an error naming the setting" do
    assert {:error, {:executable_not_found, "loge-no-z3"} = reason} =
             Z3.run("(check-sat)", executable: "loge-no-z3")

    assert Z3.format_error(reason) =~ "Logic Engine Settings"
    assert Z3.verify(executable: "loge-no-z3") == {:error, reason}
  end
end
