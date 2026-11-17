defmodule Loge.Dimacs.Engines.Asp do
  @moduledoc """
  DIMACS CNF as an answer set program: a choice over the atoms of the variables and,
  per clause, the constraint that it is not false (`Loge.Dimacs.Program`). The answer
  sets are the models of the input, so the status is `:equivalent`.

      iex> {:ok, outcome} = Loge.Dimacs.Engines.Asp.run("p cnf 2 1\\n1 -2 0\\n", [])
      iex> outcome.output.text
      "{ p1; p2 }.\\n:- not p1, p2.\\n"
  """

  @behaviour Loge.Engine

  alias Loge.Dimacs.{Cnf, Program, Solver, Translation}

  @impl true
  def id, do: :dimacs_asp

  @impl true
  def label, do: "Choices and constraints"

  @impl true
  def languages, do: [:dimacs]

  @impl true
  def task, do: {:translate, :asp, :equivalent}

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
      program = [
        Program.choice(variables),
        Enum.map(clauses, &[":- ", Program.falsified(&1), ".\n"])
      ]

      {:ok, Translation.outcome(id(), :asp, program)}
    end
  end

  @impl true
  def format_error(reason), do: Solver.format_error(reason)
end
