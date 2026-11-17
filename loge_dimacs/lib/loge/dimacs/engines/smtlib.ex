defmodule Loge.Dimacs.Engines.Smtlib do
  @moduledoc """
  DIMACS CNF as an SMT-LIB script in `QF_UF`: a Bool constant per variable, an
  assertion per clause (`Loge.Dimacs.Script`) and `(check-sat)`, the question a DIMACS
  formula asks. The output has the models of the input, so the status is `:equivalent`.

      iex> {:ok, outcome} = Loge.Dimacs.Engines.Smtlib.run("p cnf 1 1\\n-1 0\\n", [])
      iex> outcome.output.text
      "(set-logic QF_UF)\\n(declare-const p1 Bool)\\n(assert (not p1))\\n(check-sat)\\n"
  """

  @behaviour Loge.Engine

  alias Loge.Dimacs.{Cnf, Script, Solver, Translation}

  @impl true
  def id, do: :dimacs_smtlib

  @impl true
  def label, do: "Boolean constants"

  @impl true
  def languages, do: [:dimacs]

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
    with {:ok, %Cnf{variables: variables, clauses: clauses}} <- Cnf.from_input(input) do
      script = [
        "(set-logic QF_UF)\n",
        Script.constants(1..variables//1),
        Enum.map(clauses, &["(assert ", Script.clause(&1), ")\n"]),
        "(check-sat)\n"
      ]

      {:ok, Translation.outcome(id(), :smtlib, script)}
    end
  end

  @impl true
  def format_error(reason), do: Solver.format_error(reason)
end
