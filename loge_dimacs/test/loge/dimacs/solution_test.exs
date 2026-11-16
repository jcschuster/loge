defmodule Loge.Dimacs.SolutionTest do
  use ExUnit.Case, async: true

  alias Loge.Dimacs.Solution

  doctest Solution

  test "models one after another, each up to its zero" do
    assert %Solution{status: :satisfiable, models: [[1, 2], [-1, 2]]} =
             Solution.read("v 1 2 0\nv -1\nv 2 0\ns SATISFIABLE\n")
  end

  test "QDIMACS answers and certificates, with or without a closing zero" do
    assert Solution.read("s cnf 1 2 2\nV -2 0\nV 1\n") ==
             %Solution{status: :satisfiable, models: [], costs: [], certificate: [-2, 1]}

    assert %Solution{status: :unsatisfiable} = Solution.read("s cnf 0 1 1\n")
    assert %Solution{status: :unknown} = Solution.read("s cnf -1 1 1\n")
  end

  test "no status line" do
    assert %Solution{status: nil, models: []} = Solution.read("c killed\n")
  end
end
