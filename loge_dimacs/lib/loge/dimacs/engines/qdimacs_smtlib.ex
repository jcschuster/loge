defmodule Loge.Dimacs.Engines.QdimacsSmtlib do
  @moduledoc """
  QDIMACS as an SMT-LIB script in `UF`: one assertion with the quantifier sets of the
  prefix, outermost first, over the conjunction of the clauses (`Loge.Dimacs.Script`),
  and `(check-sat)`. A variable no set binds is a Bool constant, existential as QDIMACS
  reads it. The script is satisfiable exactly when the formula is true, with the same
  values for the free variables, so the status is `:equivalent`.

      iex> {:ok, outcome} = Loge.Dimacs.Engines.QdimacsSmtlib.run("p cnf 2 1\\na 1 0\\ne 2 0\\n-1 2 0\\n", [])
      iex> outcome.output.text
      "(set-logic UF)\\n(assert (forall ((p1 Bool)) (exists ((p2 Bool)) (or (not p1) p2))))\\n(check-sat)\\n"
  """

  @behaviour Loge.Engine

  alias Loge.Dimacs.{Qdimacs, Script, Solver, Translation}

  @impl true
  def id, do: :qdimacs_smtlib

  @impl true
  def label, do: "Quantified formula"

  @impl true
  def languages, do: [:qdimacs]

  @impl true
  def task, do: {:translate, :smtlib, :equivalent}

  @impl true
  def config_schema, do: []

  @impl true
  def configure(_settings), do: :ok

  @impl true
  def verify(_options), do: :ok

  @impl true
  def roles, do: []

  @impl true
  def controls, do: []

  @impl true
  def run(input, _options) do
    with {:ok, %Qdimacs{variables: variables, prefix: prefix, clauses: clauses}} <-
           Qdimacs.from_input(input) do
      bound = Enum.flat_map(prefix, fn {_quantifier, set} -> set end)

      script = [
        "(set-logic UF)\n",
        Script.constants(Enum.reject(1..variables//1, &(&1 in bound))),
        "(assert ",
        List.foldr(prefix, Script.conjunction(clauses), &quantified/2),
        ")\n(check-sat)\n"
      ]

      {:ok, Translation.outcome(id(), :smtlib, script)}
    end
  end

  @impl true
  def format_error(reason), do: Solver.format_error(reason)

  defp quantified({quantifier, set}, term) do
    [
      ?(,
      Atom.to_string(quantifier),
      " (",
      Enum.map(set, &[?(, Script.constant(&1), " Bool)"]),
      ") ",
      term,
      ?)
    ]
  end
end
