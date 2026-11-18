defmodule Loge.Smtlib.Engines.DimacsTest do
  use ExUnit.Case, async: true

  alias Loge.{Config.Field, Control, Diagnostic, Outcome, Range, Source}
  alias Loge.Smtlib.Engines.Dimacs

  @moduletag :tmp_dir

  defp answering(directory, script) do
    path = Path.join(directory, "solver")
    File.write!(path, "#!/bin/sh\n" <> script)
    File.chmod!(path, 0o755)
    path
  end

  defp printing(directory, output),
    do: answering(directory, "cat <<'END'\n" <> output <> "\nEND\n")

  test "describes itself and is registered" do
    assert Dimacs.id() == :smtlib_dimacs
    assert Dimacs.languages() == [:smtlib]
    assert Dimacs.task() == {:translate, :dimacs, :equi_satisfiable}
    assert Dimacs.roles() == []
    assert [%Field{key: :executable, default: "z3"}] = Dimacs.config_schema()
    assert [%Control{key: :time_limit, default: 10}] = Dimacs.controls()

    assert %{engine: Dimacs, from: :smtlib, to: :dimacs, preserves: :equi_satisfiable} in Loge.Registry.translations()
  end

  test "the clauses of the goal are the output, a variable per constant", %{tmp_dir: directory} do
    assert {:ok,
            %Outcome{
              status: :equi_satisfiable,
              problem: :translation,
              engine: :smtlib_dimacs,
              output: %Source{language: :dimacs, text: text},
              details: %{atoms: atoms}
            }} =
             Dimacs.run("(declare-const p Bool)",
               executable:
                 printing(directory, """
                 (goals
                 (goal
                   (or p k!0)
                   (or (not |a b|) (not p))
                   k!0
                   true
                   :precision precise :depth 3)
                 )
                 """)
             )

    assert text == "c 1 p\nc 2 k!0\nc 3 a b\np cnf 3 3\n1 2 0\n-3 -1 0\n2 0\n"
    assert atoms == %{1 => "p", 2 => "k!0", 3 => "a b"}
  end

  test "a goal that is false is the empty clause and an empty goal no clause", %{
    tmp_dir: directory
  } do
    assert {:ok, %Outcome{output: %Source{text: "p cnf 0 1\n0\n"}}} =
             Dimacs.run("",
               executable:
                 printing(directory, "(goals\n(goal\n  false\n  :precision precise :depth 1)\n)")
             )

    assert {:ok, %Outcome{output: %Source{text: "p cnf 0 0\n"}}} =
             Dimacs.run("",
               executable: printing(directory, "(goals\n(goal\n  :precision precise :depth 1)\n)")
             )
  end

  test "what z3 leaves that is no clause is outside the fragment", %{tmp_dir: directory} do
    assert {:ok,
            %Outcome{
              status: :inappropriate,
              output: nil,
              raw: raw,
              views: [{:diagnostics, [diagnostic]}]
            }} =
             Dimacs.run("",
               executable:
                 printing(
                   directory,
                   "(goals (goal (or p (not (<= x 3))) (f p) :precision precise :depth 3))"
                 )
             )

    assert raw =~ "(goals"
    assert diagnostic.message =~ "(or p (not (<= x 3))), (f p)"
  end

  test "a command that changes the assertions other than by asserting is outside", %{
    tmp_dir: directory
  } do
    assert {:ok,
            %Outcome{
              status: :inappropriate,
              views: [
                {:diagnostics,
                 [%Diagnostic{code: "fragment", range: %Range{line: 2}, message: message}]}
              ]
            }} =
             Dimacs.run("(declare-const p Bool)\n(push 1)\n(assert p)\n",
               executable: printing(directory, "")
             )

    assert message =~ "`push`"
  end

  test "an invalid script, an error of the solver, no goal and a missing solver are errors", %{
    tmp_dir: directory
  } do
    assert {:error, {:invalid_script, _diagnostics}} =
             Dimacs.run("(assert", executable: printing(directory, ""))

    assert {:error, {:solver, ["line 1 column 9: unknown constant q"]} = reason} =
             Dimacs.run("(assert q)",
               executable:
                 printing(
                   directory,
                   "(error \"line 1 column 9: unknown constant q\")\n(goals (goal :precision precise :depth 1))"
                 )
             )

    assert Dimacs.format_error(reason) == "z3 reported: line 1 column 9: unknown constant q"

    assert {:error, {:no_goal, "sat\n"} = reason} =
             Dimacs.run("(assert true)", executable: printing(directory, "sat"))

    assert Dimacs.format_error(reason) =~ "is the executable z3?"

    assert {:error, {:executable_not_found, "loge-no-z3"}} =
             Dimacs.run("(assert true)", executable: "loge-no-z3")
  end

  test "past the time limit the solver is killed", %{tmp_dir: directory} do
    assert {:ok, %Outcome{status: :timeout, output: nil}} =
             Dimacs.run("(assert true)",
               executable: answering(directory, "exec sleep 1000\n"),
               time_limit: 1
             )
  end

  describe "with z3" do
    @describetag :z3

    test "bit-vectors become clauses, and questions are left out" do
      assert {:ok,
              %Outcome{
                status: :equi_satisfiable,
                output: %Source{text: text},
                details: %{atoms: atoms}
              }} =
               Dimacs.run(
                 """
                 (set-logic QF_BV)
                 (declare-const a (_ BitVec 2))
                 (declare-const p Bool)
                 (assert (or p (= (bvadd a #b01) #b00)))
                 (assert (not p))
                 (check-sat)
                 (get-model)
                 """,
                 []
               )

      assert text =~ ~r/\Ac 1 p\nc 2 k!\d+\nc 3 k!\d+\np cnf 3 3\n1 2 0\n1 3 0\n-1 0\n\z/
      assert atoms[1] == "p"
    end

    test "an unsatisfiable script is the empty clause, and integers are outside" do
      assert {:ok, %Outcome{output: %Source{text: "p cnf 0 1\n0\n"}}} =
               Dimacs.run("(declare-const p Bool)(assert p)(assert (not p))", [])

      assert {:ok, %Outcome{status: :inappropriate}} =
               Dimacs.run(
                 "(declare-const x Int)(declare-const p Bool)(assert (or p (> x 3)))",
                 []
               )
    end

    test "z3's errors are the run's" do
      assert {:error, {:solver, [message]}} = Dimacs.run("(assert q)", [])
      assert message =~ "unknown constant q"
    end
  end
end
