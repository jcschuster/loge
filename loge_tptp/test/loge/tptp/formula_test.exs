defmodule Loge.Tptp.FormulaTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Loge.Tptp.Formula
  alias Tptp.Printer.Canonical

  doctest Formula

  defp read(language \\ "fof", text) do
    {:ok, statement, []} = Tptp.Parser.statement_from_string("#{language}(a, axiom, #{text}).")
    Formula.from_node(statement.formula)
  end

  defp p(name), do: {:predicate, {:plain, name}, []}

  test "reads the connectives, writing out those that abbreviate others" do
    assert read("(p & q) | ~ r") == {:ok, {:or, {:and, p("p"), p("q")}, {:not, p("r")}}}
    assert read("p => q") == {:ok, {:implies, p("p"), p("q")}}
    assert read("p <= q") == {:ok, {:implies, p("q"), p("p")}}
    assert read("p <=> q") == {:ok, {:iff, p("p"), p("q")}}
    assert read("p <~> q") == {:ok, {:not, {:iff, p("p"), p("q")}}}
    assert read("p ~| q") == {:ok, {:not, {:or, p("p"), p("q")}}}
    assert read("p ~& q") == {:ok, {:not, {:and, p("p"), p("q")}}}
    assert read("$true & $false") == {:ok, {:and, true, false}}
  end

  test "reads quantifiers with their variables and drops parentheses" do
    assert read("![X, Y]: ?[Z]: ((p(X, Y, Z)))") ==
             {:ok,
              {:forall, ["X", "Y"],
               {:exists, ["Z"],
                {:predicate, {:plain, "p"}, [variable: "X", variable: "Y", variable: "Z"]}}}}
  end

  test "reads terms: a plain symbol by its word, the others as written" do
    assert read("'p'(f('a b'), \"d\", 1/2) & X != $sum(1, 2.0) & $$s") ==
             {:ok,
              {:and,
               {:and,
                {:predicate, {:plain, "p"},
                 [
                   {:function, {:plain, "f"}, [{:function, {:plain, "a b"}, []}]},
                   {:distinct_object, "\"d\""},
                   {:number, "1/2"}
                 ]},
                {:not,
                 {:equal, {:variable, "X"},
                  {:function, {:defined, "$sum"}, [number: "1", number: "2.0"]}}}},
               {:predicate, {:system, "$$s"}, []}}}
  end

  test "reads a clause as a disjunction" do
    assert read("cnf", "p(X) | ~ q | X != a | r") ==
             {:ok,
              {:or,
               {:or, {:or, {:predicate, {:plain, "p"}, [variable: "X"]}, {:not, p("q")}},
                {:not, {:equal, {:variable, "X"}, {:function, {:plain, "a"}, []}}}}, p("r")}}
  end

  test "reads a tff formula, a typed variable with its type" do
    assert read(
             "tff",
             "![X: human, Y]: (p(X, f(X, Y, c)) => ?[Z: $i]: (g(Z) = c & ~ q & Z != c))"
           ) ==
             {:ok,
              {:forall, [{"X", {:plain, "human"}}, "Y"],
               {:implies,
                {:predicate, {:plain, "p"},
                 [
                   {:variable, "X"},
                   {:function, {:plain, "f"},
                    [{:variable, "X"}, {:variable, "Y"}, {:function, {:plain, "c"}, []}]}
                 ]},
                {:exists, [{"Z", {:defined, "$i"}}],
                 {:and,
                  {:and,
                   {:equal, {:function, {:plain, "g"}, [variable: "Z"]},
                    {:function, {:plain, "c"}, []}}, {:not, p("q")}},
                  {:not, {:equal, {:variable, "Z"}, {:function, {:plain, "c"}, []}}}}}}}}

    assert {:error, %Tptp.Node{kind: :tff_atom_typing}} = read("tff", "c: human")
  end

  test "closes a formula over its free variables only" do
    assert Formula.closure(
             {:forall, ["X"], {:predicate, {:plain, "p"}, [variable: "X", variable: "Y"]}}
           ) ==
             {:forall, ["Y"],
              {:forall, ["X"], {:predicate, {:plain, "p"}, [variable: "X", variable: "Y"]}}}

    assert Formula.closure(p("q")) == p("q")
  end

  test "a sequent is not a formula" do
    assert {:error, %Tptp.Node{kind: :fof_sequent}} = read("[p] --> [q]")
  end

  test "a variable in the place of a formula is not first-order" do
    assert {:error, %Tptp.Node{kind: :variable}} = read("tff", "![X: $o]: (~ X)")
  end

  property "a formula is read back from the text of its tree" do
    check all(formula <- formula()) do
      assert formula |> Formula.to_node() |> Canonical.to_string() |> read() == {:ok, formula}
    end
  end

  defp formula do
    tree(atomic(), fn inner ->
      one_of([
        map(inner, &negation/1),
        map({member_of([:and, :or, :implies, :iff]), inner, inner}, & &1),
        map(
          {member_of([:forall, :exists]), list_of(variable_name(), min_length: 1, max_length: 3),
           inner},
          & &1
        )
      ])
    end)
  end

  defp negation({:not, {:equal, _left, _right}} = formula), do: {:not, {:not, formula}}
  defp negation(formula), do: {:not, formula}

  defp atomic do
    one_of([
      boolean(),
      map({symbol(), list_of(a_term(), max_length: 2)}, fn {symbol, arguments} ->
        {:predicate, symbol, arguments}
      end),
      map({a_term(), a_term()}, fn {left, right} -> {:equal, left, right} end)
    ])
  end

  defp a_term do
    tree(
      one_of([
        map(variable_name(), &{:variable, &1}),
        map(symbol(), &{:function, &1, []}),
        map(member_of(["1", "-2", "1/2", "2.5"]), &{:number, &1}),
        constant({:distinct_object, "\"d\""})
      ]),
      fn inner ->
        map({symbol(), list_of(inner, min_length: 1, max_length: 3)}, fn {symbol, arguments} ->
          {:function, symbol, arguments}
        end)
      end
    )
  end

  defp symbol, do: map(member_of(["p", "q", "f", "a b", "It's", "X"]), &{:plain, &1})
  defp variable_name, do: member_of(["X", "Y", "Z"])
end
