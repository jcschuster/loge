defmodule Loge.Dimacs.SolverTest do
  use ExUnit.Case, async: true

  alias Loge.{Diagnostic, Outcome, Range}
  alias Loge.Dimacs.Solver

  test "a satisfiability outcome has the status line's answer and the models" do
    assert Solver.satisfiability(:fake, "s SATISFIABLE\nv 1 -2 0\n", :finished) == %Outcome{
             status: :satisfiable,
             problem: :satisfiability,
             raw: "s SATISFIABLE\nv 1 -2 0\n",
             engine: :fake,
             views: [{:models, [[1, -2]]}]
           }

    assert %Outcome{status: :unsatisfiable, views: []} =
             Solver.satisfiability(:fake, "s UNSATISFIABLE\n", :finished)
  end

  test "no answer is unknown, or a timeout when the time limit stopped the run" do
    assert %Outcome{status: :unknown} = Solver.satisfiability(:fake, "s UNKNOWN\n", :finished)
    assert %Outcome{status: :timeout} = Solver.satisfiability(:fake, "c searching\n", :stopped)
  end

  test "an optimum has a badge, the cost of the last model and the improving models" do
    output = "v -1 2 0\no 3\nv 1 -2 0\no 2\ns OPTIMUM FOUND\n"

    assert %Outcome{status: :satisfiable, views: views} =
             Solver.optimisation(:fake, output, :finished)

    assert views == [
             {:badge, "optimum found", :positive},
             {:badge, "cost 2", :neutral},
             {:models, [[-1, 2], [1, -2]]}
           ]

    assert %Outcome{status: :satisfiable, views: [{:badge, "cost 3", :neutral}, _models]} =
             Solver.optimisation(:fake, "v -1 2 0\no 3\ns SATISFIABLE\n", :stopped)
  end

  test "a quantified formula's truth, with its partial certificate" do
    assert %Outcome{
             status: :satisfiable,
             views: [{:titled, "Partial certificate", {:models, [[1, -2]]}}]
           } = Solver.quantified(:fake, "s cnf 1 2 1\nV 1 0\nV -2 0\n", :finished)

    assert %Outcome{status: :unsatisfiable, views: []} =
             Solver.quantified(:fake, "s cnf 0 2 1\n", :finished)
  end

  test "errors read as sentences" do
    diagnostic = Diagnostic.new("DIMACS013", :error, Range.new(2), "innermost")

    assert Solver.format_error({:invalid_qdimacs, [diagnostic]}) ==
             "Invalid QDIMACS:\nline 2: innermost"

    assert Solver.format_error({:executable_not_found, "kissat"}) =~
             "kissat was not found on PATH"
  end
end
