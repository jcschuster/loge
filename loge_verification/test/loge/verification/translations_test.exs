defmodule Loge.Verification.TranslationsTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  import Loge.Verification

  alias Loge.Asp.Engines, as: Asp
  alias Loge.Dimacs.Engines, as: Dimacs
  alias Loge.Egglog.Engines, as: Egglog
  alias Loge.Prolog.Engines, as: Prolog
  alias Loge.Smtlib.Engines, as: Smtlib
  alias Loge.Tptp.Engines, as: Tptp
  alias Loge.Turtle.Engines, as: Turtle
  alias Loge.Verification.Generators

  @moduletag timeout: 600_000

  @runs String.to_integer(System.get_env("LOGE_VERIFICATION_RUNS", "30"))

  @checked [
    Dimacs.Tptp,
    Dimacs.Smtlib,
    Dimacs.Asp,
    Dimacs.WcnfAsp,
    Dimacs.QdimacsSmtlib,
    Tptp.Clausify,
    Tptp.Ground,
    Tptp.Dimacs,
    Tptp.Smtlib,
    Tptp.Prolog,
    Tptp.Fof,
    Tptp.Tff,
    Tptp.Thf,
    Tptp.Untyped,
    Smtlib.Tptp,
    Smtlib.Dimacs,
    Asp.Dimacs,
    Prolog.Tptp,
    Prolog.Asp,
    Prolog.Egglog,
    Turtle.Tptp,
    Turtle.Prolog,
    Turtle.Asp
  ]

  defp agrees(answer, reference, input) do
    assert answer == reference,
           "the output is #{answer} where the input is #{reference}:\n" <> text(input)
  end

  defp agrees_if_decided(:undecided, _reference, _input), do: :ok
  defp agrees_if_decided(_answer, :undecided, _input), do: :ok
  defp agrees_if_decided(answer, reference, input), do: agrees(answer, reference, input)

  defp text(input), do: input |> Loge.Input.to_iodata() |> IO.iodata_to_binary()

  test "every registered translation has a check here" do
    registered = Loge.Registry.translations() |> Enum.map(& &1.engine) |> Enum.uniq()
    assert Enum.sort(registered) == Enum.sort(@checked)
  end

  @tag :vampire
  test "Vampire, the judge of the TPTP outputs, decides a theorem and a non-theorem" do
    assert vampire("fof(a, axiom, p). fof(c, conjecture, p | q).") == :unsatisfiable
    assert vampire("fof(a, axiom, p | q). fof(c, conjecture, p).") == :satisfiable
  end

  describe "DIMACS, against clasp on the input" do
    property "CNF as ASP, as TPTP and back, and as ASP completed" do
      check all(cnf <- Generators.cnf(), max_runs: @runs) do
        reference = solve(cnf, [Dimacs.Clasp])
        agrees(solve(cnf, [Dimacs.Asp, Asp.Clingo]), reference, cnf)
        agrees(solve(cnf, [Dimacs.Tptp, Tptp.Dimacs, Dimacs.Clasp]), reference, cnf)
        agrees(solve(cnf, [Dimacs.Asp, Asp.Dimacs, Dimacs.Clasp]), reference, cnf)
      end
    end

    property "WCNF as ASP has the optimum of clasp's MaxSAT" do
      check all(wcnf <- Generators.wcnf(), max_runs: @runs) do
        maxsat = pipe(wcnf, [Dimacs.ClaspMaxsat])
        asp = pipe(wcnf, [Dimacs.WcnfAsp, Asp.Clingo])
        agrees(answer(asp), answer(maxsat), wcnf)

        if answer(maxsat) == :satisfiable do
          assert clingo_cost(asp) == maxsat_cost(maxsat), text(wcnf)
        end
      end
    end

    @tag :z3
    property "CNF as SMT-LIB under z3, bit-blasted back, and through TPTP" do
      check all(cnf <- Generators.cnf(), max_runs: @runs) do
        reference = solve(cnf, [Dimacs.Clasp])
        agrees(solve(cnf, [Dimacs.Smtlib, Smtlib.Z3]), reference, cnf)
        agrees(solve(cnf, [Dimacs.Smtlib, Smtlib.Dimacs, Dimacs.Clasp]), reference, cnf)
        agrees(solve(cnf, [Dimacs.Tptp, Tptp.Smtlib, Smtlib.Z3]), reference, cnf)
      end
    end

    @tag :z3
    property "QDIMACS as SMT-LIB under z3 is true exactly when the formula is" do
      check all(qbf <- Generators.qbf(), max_runs: @runs) do
        reference = if true?(qbf.prefix, qbf.clauses, []), do: :satisfiable, else: :unsatisfiable
        agrees(solve(qbf, [Dimacs.QdimacsSmtlib, Smtlib.Z3]), reference, qbf)
      end
    end

    @tag :vampire
    property "CNF as TPTP, and as SMT-LIB then TF0, under Vampire" do
      check all(cnf <- Generators.cnf(), max_runs: @runs) do
        reference = solve(cnf, [Dimacs.Clasp])
        agrees(vampire(pipe(cnf, [Dimacs.Tptp])), reference, cnf)
        agrees(vampire(pipe(cnf, [Dimacs.Smtlib, Smtlib.Tptp])), reference, cnf)
      end
    end
  end

  describe "Prolog, against SWI-Prolog on the input" do
    property "Datalog as ASP, as egglog, as TPTP grounded to SAT, and back to Prolog" do
      check all(program <- Generators.datalog(recursive: false), max_runs: @runs) do
        reference = solve(program, [Prolog.Swipl])
        agrees(solve(program, [Prolog.Asp, Asp.Clingo]), reference, program)
        agrees(solve(program, [Prolog.Egglog, Egglog.Egglog]), reference, program)

        agrees(
          solve(program, [Prolog.Tptp, Tptp.Ground, Tptp.Dimacs, Dimacs.Clasp]),
          reference,
          program
        )

        agrees(solve(program, [Prolog.Tptp, Tptp.Prolog, Prolog.Swipl]), reference, program)
        agrees(solve(program, [Prolog.Asp, Asp.Dimacs, Dimacs.Clasp]), reference, program)
      end
    end

    property "recursive Datalog, where Prolog may not end: clingo, egglog and SAT agree" do
      check all(program <- Generators.datalog(recursive: true), max_runs: @runs) do
        reference = solve(program, [Prolog.Asp, Asp.Clingo])
        agrees(solve(program, [Prolog.Egglog, Egglog.Egglog]), reference, program)

        agrees(
          solve(program, [Prolog.Tptp, Tptp.Ground, Tptp.Dimacs, Dimacs.Clasp]),
          reference,
          program
        )
      end
    end

    @tag :vampire
    property "Datalog as TPTP, and that in every dialect, under Vampire" do
      check all(program <- Generators.datalog(recursive: true), max_runs: @runs) do
        reference = solve(program, [Prolog.Asp, Asp.Clingo])
        agrees(vampire(pipe(program, [Prolog.Tptp])), reference, program)

        for dialect <- [Tptp.Fof, Tptp.Tff, Tptp.Untyped] do
          agrees(vampire(pipe(program, [Prolog.Tptp, dialect])), reference, program)
        end

        agrees_if_decided(vampire(pipe(program, [Prolog.Tptp, Tptp.Thf])), reference, program)
      end
    end
  end

  describe "ASP, against clingo on the input" do
    property "a tight program completed to SAT" do
      check all(program <- Generators.tight(), max_runs: @runs) do
        agrees(solve(program, [Asp.Dimacs, Dimacs.Clasp]), solve(program, [Asp.Clingo]), program)
      end
    end
  end

  describe "TPTP" do
    @tag :z3
    property "clauses grounded to SAT, against z3 on the SMT-LIB of each dialect" do
      check all(problem <- Generators.clauses(), max_runs: @runs) do
        reference = solve(problem, [Tptp.Ground, Tptp.Dimacs, Dimacs.Clasp])

        for dialects <- [
              [],
              [Tptp.Fof],
              [Tptp.Tff],
              [Tptp.Fof, Tptp.Untyped],
              [Tptp.Tff, Tptp.Untyped]
            ] do
          agrees(solve(problem, dialects ++ [Tptp.Smtlib, Smtlib.Z3]), reference, problem)
        end
      end
    end

    @tag :vampire
    property "a first-order problem clausified and in every dialect, against Vampire on the input" do
      check all(problem <- Generators.first_order(), max_runs: @runs) do
        reference = vampire(problem)

        for translations <- [
              [Tptp.Clausify],
              [Tptp.Tff],
              [Tptp.Untyped],
              [Tptp.Clausify, Tptp.Fof]
            ] do
          agrees(vampire(pipe(problem, translations)), reference, problem)
        end

        agrees_if_decided(vampire(pipe(problem, [Tptp.Thf])), reference, problem)
      end
    end

    @tag :vampire
    property "a typed problem without its types and in TH0, against Vampire on the input" do
      check all(problem <- Generators.typed(), max_runs: @runs) do
        reference = vampire(problem)
        agrees(vampire(pipe(problem, [Tptp.Untyped])), reference, problem)
        agrees_if_decided(vampire(pipe(problem, [Tptp.Thf])), reference, problem)
      end
    end

    @tag :vampire
    @tag :z3
    property "a first-order and a typed problem as SMT-LIB under z3, against Vampire on the input" do
      check all(
              problem <- one_of([Generators.first_order(), Generators.typed()]),
              max_runs: @runs
            ) do
        agrees_if_decided(
          solve(problem, [Tptp.Smtlib, {Smtlib.Z3, time_limit: 5}]),
          vampire(problem),
          problem
        )
      end
    end
  end

  describe "SMT-LIB, against z3 on the input" do
    @describetag :z3

    property "bit-vectors blasted to SAT" do
      check all(script <- Generators.bit_vectors(), max_runs: @runs) do
        agrees(solve(script, [Smtlib.Dimacs, Dimacs.Clasp]), solve(script, [Smtlib.Z3]), script)
      end
    end

    property "uninterpreted functions as TF0 and back, and without types" do
      check all(script <- Generators.script(), max_runs: @runs) do
        reference = solve(script, [Smtlib.Z3])
        agrees(solve(script, [Smtlib.Tptp, Tptp.Smtlib, Smtlib.Z3]), reference, script)

        agrees(
          solve(script, [Smtlib.Tptp, Tptp.Untyped, Tptp.Smtlib, Smtlib.Z3]),
          reference,
          script
        )
      end
    end

    property "integer and real arithmetic as TF0 and back" do
      check all(script <- Generators.arithmetic(), max_runs: @runs) do
        agrees_if_decided(
          solve(script, [Smtlib.Tptp, Tptp.Smtlib, {Smtlib.Z3, time_limit: 5}]),
          solve(script, [{Smtlib.Z3, time_limit: 5}]),
          script
        )
      end
    end

    @tag :princess
    property "integer arithmetic as TF0 under Princess" do
      check all(script <- Generators.integer_arithmetic(), max_runs: @runs) do
        agrees_if_decided(
          princess(pipe(script, [Smtlib.Tptp])),
          solve(script, [{Smtlib.Z3, time_limit: 5}]),
          script
        )
      end
    end

    @tag :vampire
    property "uninterpreted functions as TF0 under Vampire" do
      check all(script <- Generators.script(), max_runs: @runs) do
        agrees(
          vampire(pipe(script, [Smtlib.Tptp])),
          solve(script, [Smtlib.Z3]),
          script
        )
      end
    end
  end

  describe "Turtle" do
    property "a graph has as many facts as triples, for SWI-Prolog, clingo and as SAT variables" do
      check all({graph, triples} <- Generators.graph(), triples > 0, max_runs: @runs) do
        facts = pipe(graph, [Turtle.Prolog])
        asked = Loge.source(:prolog, text(facts) <> "?- triple(S, P, O).\n")

        assert [{:titled, _goal, {:table, _variables, rows}}] =
                 pipe(asked, [{Prolog.Swipl, answers: 0}]).views

        assert length(rows) == triples, graph

        assert %{details: %{json: %{"Call" => [%{"Witnesses" => [%{"Value" => atoms}]}]}}} =
                 pipe(graph, [Turtle.Asp, Asp.Clingo])

        assert length(atoms) == triples, graph

        sat = pipe(graph, [Turtle.Tptp, Tptp.Dimacs])
        assert map_size(sat.details.atoms) == triples, graph
        agrees(solve(sat, [Dimacs.Clasp]), :satisfiable, graph)
      end
    end
  end

  defp maxsat_cost(outcome) do
    Enum.find_value(outcome.views, 0, fn
      {:badge, "cost " <> cost, _tone} -> String.to_integer(cost)
      _view -> nil
    end)
  end

  defp clingo_cost(%{details: %{json: json}}) do
    case json["Models"]["Costs"] do
      [cost] -> cost
      _none -> 0
    end
  end

  defp true?([], clauses, assignment),
    do: Enum.all?(clauses, fn clause -> Enum.any?(clause, &(&1 in assignment)) end)

  defp true?([{_quantifier, []} | prefix], clauses, assignment),
    do: true?(prefix, clauses, assignment)

  defp true?([{quantifier, [variable | rest]} | prefix], clauses, assignment) do
    values =
      Enum.map(
        [variable, -variable],
        &true?([{quantifier, rest} | prefix], clauses, [&1 | assignment])
      )

    if quantifier == :forall, do: Enum.all?(values), else: Enum.any?(values)
  end
end
