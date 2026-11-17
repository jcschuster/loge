defmodule Loge.Asp.Engines.DimacsTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Loge.{Control, Diagnostic, Outcome, Source}
  alias Loge.Asp.{Aspif, Completion}
  alias Loge.Asp.Engines.{Clingo, Dimacs}

  doctest Aspif
  doctest Completion

  test "describes itself and is registered" do
    assert Dimacs.id() == :asp_dimacs
    assert Dimacs.languages() == [:asp]
    assert Dimacs.task() == {:translate, :dimacs, :equi_satisfiable}
    assert Dimacs.roles() == []
    assert Dimacs.config_schema() == []
    assert Dimacs.configure([]) == :ok
    assert Dimacs.verify([]) == :ok
    assert [%Control{key: :time_limit, default: 10}] = Dimacs.controls()

    assert %{engine: Dimacs, from: :asp, to: :dimacs, preserves: :equi_satisfiable} in Loge.Registry.translations()
  end

  test "rules, choices and constraints are completed; atoms are named in comments" do
    assert {:ok,
            %Outcome{
              status: :equi_satisfiable,
              problem: :translation,
              engine: :asp_dimacs,
              output: %Source{language: :dimacs, text: text},
              details: details
            }} = Dimacs.run("{ a; b }.\nc :- a, not b.\n:- c, b.\nf(1).\n", [])

    assert text == """
           c true f(1)
           c 2 a
           c 3 b
           c 4 c
           p cnf 5 6
           1 0
           4 3 -2 0
           -3 -4 0
           -5 -3 0
           -5 2 0
           -4 5 0
           """

    assert details == %{atoms: %{2 => "a", 3 => "b", 4 => "c"}, facts: ["f(1)"]}
  end

  test "variables are grounded, with included programs" do
    assert {:ok, %Outcome{output: %Source{text: text}}} =
             Dimacs.run("#include \"facts\".\n{ in(X) } :- node(X).\n",
               includes: %{"facts" => Loge.source(:asp, "node(1..2).")}
             )

    assert text =~ "c true node(1)\nc true node(2)\n"
    assert text =~ "c 3 in(1)\nc 4 in(2)\np cnf 4 2\n1 0\n2 0\n"
  end

  test "a program that is not tight, and what completion does not cover, are outside" do
    for {program, sentence} <- [
          {"{ r }.\np :- q.\nq :- p.\np :- r.\n", "not tight: "},
          {"a ; b.\n", "disjunction"},
          {"{ a; b }.\nc :- 1 { a; b } 1.\n", "aggregate"},
          {"{ a }.\n#minimize { 1 : a }.\n", "#minimize"},
          {"#external a.\n", "#external"}
        ] do
      assert {:ok,
              %Outcome{
                status: :inappropriate,
                output: nil,
                views: [{:diagnostics, [%Diagnostic{code: "fragment", message: message}]}]
              }} = Dimacs.run(program, [])

      assert message =~ sentence
    end
  end

  test "the atoms of a loop are named" do
    assert {:ok, %Outcome{views: [{:diagnostics, [%Diagnostic{message: message}]}]}} =
             Dimacs.run("{ r }.\np :- q.\nq :- p.\np :- r.\n", [])

    assert message =~ ~r/not tight: (p, q|q, p) depend/
  end

  test "a program that does not ground is an error with its diagnostics" do
    assert {:error, {:invalid_program, [%Diagnostic{severity: :error} | _]} = reason} =
             Dimacs.run("p(X) :- q.\n", [])

    assert Dimacs.format_error(reason) =~ "Invalid ASP program:\nline 1"
  end

  test "grounding past the time limit is stopped" do
    assert {:ok, %Outcome{status: :timeout, output: nil}} =
             Dimacs.run("p(0).\np(X+1) :- p(X).\n", time_limit: 1)
  end

  property "the models of the output, on the atoms, are as many as the answer sets" do
    check all(program <- program(), max_runs: 40) do
      assert {:ok,
              %Outcome{
                status: :equi_satisfiable,
                output: %Source{text: text},
                details: %{atoms: atoms}
              }} =
               Dimacs.run(program, [])

      assert {:ok, %Outcome{details: %{json: json}}} = Clingo.run(program, models: 0)
      assert projected_models(text, Map.keys(atoms)) == json["Models"]["Number"]
    end
  end

  defp program do
    atoms = ["a", "b", "c", "d"]

    rule =
      gen all(
            {head, index} <- member_of(Enum.with_index(atoms)),
            positive <- list_of(member_of(Enum.drop(atoms, index + 1) ++ ["a"]), max_length: 2),
            negative <- list_of(member_of(atoms), max_length: 2),
            kind <- member_of([:rule, :choice, :constraint])
          ) do
        positive = if index == 0, do: [], else: positive -- ["a"]
        body = Enum.join(positive ++ Enum.map(negative, &("not " <> &1)), ", ")

        case {kind, body} do
          {:rule, ""} -> "#{head}."
          {:rule, body} -> "#{head} :- #{body}."
          {:choice, ""} -> "{ #{head} }."
          {:choice, body} -> "{ #{head} } :- #{body}."
          {:constraint, ""} -> "{ #{head} }."
          {:constraint, body} -> ":- #{body}."
        end
      end

    map(list_of(rule, min_length: 1, max_length: 6), &Enum.join(&1, "\n"))
  end

  defp projected_models(text, atoms) do
    ["p", "cnf", variables, _count] =
      text |> String.split("\n") |> Enum.find(&String.starts_with?(&1, "p cnf")) |> String.split()

    clauses =
      for line <- String.split(text, "\n", trim: true),
          not String.starts_with?(line, ["c", "p"]) do
        line |> String.split() |> Enum.map(&String.to_integer/1) |> Enum.drop(-1)
      end

    1..String.to_integer(variables)//1
    |> Enum.reduce([[]], fn n, partial -> for a <- partial, l <- [n, -n], do: [l | a] end)
    |> Enum.filter(fn assignment ->
      Enum.all?(clauses, fn clause -> Enum.any?(clause, &(&1 in assignment)) end)
    end)
    |> Enum.map(fn assignment -> Enum.filter(assignment, &(abs(&1) in atoms)) end)
    |> Enum.uniq()
    |> length()
  end
end
