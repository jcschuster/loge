defmodule Loge.Dimacs.Engines.WcnfAsp do
  @moduledoc """
  WCNF as an answer set program: a choice over the atoms of the variables, a
  constraint per hard clause and, per soft clause, a weak constraint that costs its
  weight when the clause is false (`Loge.Dimacs.Program`). The position of a soft
  clause among the soft clauses is the term of its weak constraint, so two soft clauses
  alike in weight and literals cost twice. The answer sets are the assignments
  satisfying the hard clauses and their costs are the same, so the status is
  `:equivalent`.

      iex> {:ok, outcome} = Loge.Dimacs.Engines.WcnfAsp.run("h 1 2 0\\n3 -1 0\\n", [])
      iex> outcome.output.text
      "{ p1; p2 }.\\n:- not p1, not p2.\\n:~ p1. [3@0, 1]\\n"
  """

  @behaviour Loge.Engine

  alias Loge.Dimacs.{Program, Wcnf, Solver, Translation}

  @impl true
  def id, do: :wcnf_asp

  @impl true
  def label, do: "Weak constraints"

  @impl true
  def languages, do: [:wcnf]

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
    with {:ok, %Wcnf{variables: variables, hard: hard, soft: soft}} <- Wcnf.from_input(input) do
      program = [
        Program.choice(variables),
        Enum.map(hard, &[":- ", Program.falsified(&1), ".\n"]),
        soft |> Enum.with_index(1) |> Enum.map(&weak/1)
      ]

      {:ok, Translation.outcome(id(), :asp, program)}
    end
  end

  @impl true
  def format_error(reason), do: Solver.format_error(reason)

  defp weak({{weight, clause}, position}) do
    [
      ":~ ",
      Program.falsified(clause),
      ". [",
      Integer.to_string(weight),
      "@0, ",
      Integer.to_string(position),
      "]\n"
    ]
  end
end
