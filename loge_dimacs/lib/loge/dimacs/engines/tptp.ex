defmodule Loge.Dimacs.Engines.Tptp do
  @moduledoc """
  DIMACS CNF as TPTP: the clause at position `n` is the statement `cnf(cn, axiom, …)`
  over the propositional atoms `p1`, `p2`, … of its variables, and the empty clause is
  `$false`. The output has the models of the input, so the status is `:equivalent`.

      iex> {:ok, outcome} = Loge.Dimacs.Engines.Tptp.run("p cnf 2 2\\n1 -2 0\\n2 0\\n", [])
      iex> outcome.output.text
      "cnf(c1, axiom, p1 | ~p2).\\ncnf(c2, axiom, p2).\\n"
  """

  @behaviour Loge.Engine

  alias Loge.Dimacs.{Cnf, Solver, Translation}

  @impl true
  def id, do: :dimacs_tptp

  @impl true
  def label, do: "Clauses"

  @impl true
  def languages, do: [:dimacs]

  @impl true
  def task, do: {:translate, :tptp, :equivalent}

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
    with {:ok, %Cnf{clauses: clauses}} <- Cnf.from_input(input) do
      statements =
        clauses
        |> Enum.with_index(1)
        |> Enum.map(fn {clause, n} ->
          ["cnf(c", Integer.to_string(n), ", axiom, ", clause(clause), ").\n"]
        end)

      {:ok, Translation.outcome(id(), :tptp, statements)}
    end
  end

  @impl true
  def format_error(reason), do: Solver.format_error(reason)

  defp clause([]), do: "$false"
  defp clause(clause), do: Enum.map_intersperse(clause, " | ", &literal/1)

  defp literal(literal) when literal > 0, do: [?p, Integer.to_string(literal)]
  defp literal(literal), do: ["~p", Integer.to_string(-literal)]
end
