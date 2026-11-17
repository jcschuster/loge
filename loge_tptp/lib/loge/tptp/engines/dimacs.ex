defmodule Loge.Tptp.Engines.Dimacs do
  @moduledoc """
  Ground clauses without equality as DIMACS CNF: each ground atom is a variable,
  numbered in the order the atoms first occur, and each clause a line. The atom of a
  variable is in a comment line `c <variable> <atom>` before the problem line and in
  `details.atoms`, a map from the variable to the atom's text. A clause with `$true`
  holds and is left out.

  A propositional model of the output is a Herbrand model of the input and the other
  way round, so the status is `:equi_satisfiable`.

  A statement that is not `cnf`, a clause with a variable and a clause with an equation
  are outside the fragment: the outcome is `:inappropriate` (`Loge.Tptp.Translation`).
  `Loge.Tptp.Engines.Ground` removes variables; equality has no translation yet.

      iex> {:ok, outcome} = Loge.Tptp.Engines.Dimacs.run("cnf(a, axiom, p(a) | ~ q). cnf(b, axiom, q).", [])
      iex> outcome.output.text
      "c 1 p(a)\\nc 2 q\\np cnf 2 2\\n1 -2 0\\n2 0\\n"
      iex> outcome.details.atoms
      %{1 => "p(a)", 2 => "q"}
  """

  @behaviour Loge.Engine

  alias Loge.Tptp.{Clause, Formula, Translation}
  alias Tptp.Printer.Canonical

  @impl true
  def id, do: :tptp_dimacs

  @impl true
  def label, do: "Propositional atoms"

  @impl true
  def languages, do: [:tptp]

  @impl true
  def task, do: {:translate, :dimacs, :equi_satisfiable}

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
  def run(input, options) do
    with {:ok, unit} <- Translation.read(input, options) do
      {:ok,
       case Translation.statements(unit, &clause/1) do
         {:ok, clauses} -> translated(clauses)
         {:inappropriate, diagnostics} -> Translation.inappropriate(id(), diagnostics)
       end}
    end
  end

  @impl true
  def format_error(reason), do: Translation.format_error(reason)

  defp translated(clauses) do
    clauses = Enum.reject(clauses, &(true in &1))

    numbers =
      for clause <- clauses, literal <- clause, reduce: %{} do
        numbers -> Map.put_new(numbers, atom(literal), map_size(numbers) + 1)
      end

    atoms = numbers |> Enum.sort_by(fn {_atom, number} -> number end)

    text = [
      Enum.map(atoms, fn {atom, number} -> ["c ", Integer.to_string(number), ?\s, atom, ?\n] end),
      "p cnf #{map_size(numbers)} #{length(clauses)}\n",
      Enum.map(clauses, fn clause ->
        [Enum.map(clause, &[literal(&1, numbers), ?\s]), "0\n"]
      end)
    ]

    Translation.translated(id(), :equi_satisfiable, :dimacs, text, %{
      atoms: Map.new(atoms, fn {atom, number} -> {number, atom} end)
    })
  end

  defp clause(statement) do
    with {:ok, clause} <- Translation.clause(statement) do
      case Enum.find_value(clause, &outside/1) do
        nil -> {:ok, clause}
        message -> {:outside, message}
      end
    end
  end

  defp outside(true), do: nil
  defp outside({:not, atom}), do: outside(atom)

  defp outside({:equal, _left, _right}),
    do: "This clause has an equation, which is no propositional atom."

  defp outside({:predicate, _symbol, arguments}) do
    if Enum.all?(arguments, &ground?/1),
      do: nil,
      else: "This clause has a variable; ground the problem first."
  end

  defp ground?({:variable, _name}), do: false
  defp ground?({:function, _symbol, arguments}), do: Enum.all?(arguments, &ground?/1)
  defp ground?(_term), do: true

  defp atom(literal) do
    {_polarity, atom} = Clause.polarity(literal)
    atom |> Formula.to_node() |> Canonical.to_string()
  end

  defp literal(literal, numbers) do
    case Clause.polarity(literal) do
      {:positive, _atom} -> Integer.to_string(numbers[atom(literal)])
      {:negative, _atom} -> [?-, Integer.to_string(numbers[atom(literal)])]
    end
  end
end
