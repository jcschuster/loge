defmodule Loge.Tptp.Engines.Ground do
  @moduledoc """
  The ground instances of clauses without function symbols: every clause with each
  assignment of the problem's constants to its variables, as `cnf` statements named
  `g1`, `g2`, … with the role of the clause they instantiate. A problem with variables
  and no constant gets one, named `c` or the first of `c1`, `c2`, … no predicate has.

  The input is unsatisfiable exactly when its ground instances are (Herbrand's theorem;
  with equality, a model of the instances restricted to what the constants denote is a
  model of the clauses), so the status is `:equi_satisfiable`. There are
  `constants ^ variables` instances of a clause, and all of them are written.

  A statement that is not `cnf`, and a clause with a function symbol of arity above 0,
  a number, a distinct object or a defined or system symbol, are outside the fragment:
  the outcome is `:inappropriate` (`Loge.Tptp.Translation`).

      iex> {:ok, outcome} = Loge.Tptp.Engines.Ground.run("cnf(a, axiom, p(X) | ~ q(b)). cnf(b, axiom, q(c)).", [])
      iex> outcome.output.text
      "cnf(g1, axiom, p(b) | ~q(b)).\\ncnf(g2, axiom, p(c) | ~q(b)).\\ncnf(g3, axiom, q(c)).\\n"
  """

  @behaviour Loge.Engine

  alias Loge.Tptp.{Clause, Translation}
  alias Tptp.Printer.Canonical
  alias Tptp.Statement.Annotated

  @impl true
  def id, do: :ground

  @impl true
  def label, do: "Ground instances"

  @impl true
  def languages, do: [:tptp]

  @impl true
  def task, do: {:translate, :tptp, :equi_satisfiable}

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
    universe = universe(clauses)

    statements =
      clauses
      |> Stream.flat_map(fn {role, clause} ->
        clause |> instances(universe) |> Stream.map(&{role, &1})
      end)
      |> Stream.with_index(1)
      |> Enum.map(fn {{role, instance}, position} ->
        [Canonical.to_iodata(Clause.statement("g#{position}", role, instance)), ?\n]
      end)

    Translation.translated(id(), :equi_satisfiable, :tptp, statements)
  end

  defp clause(statement) do
    with {:ok, clause} <- Translation.clause(statement) do
      if Enum.all?(clause, &function_free?/1),
        do: {:ok, {Annotated.role_word(statement), clause}},
        else:
          {:outside,
           "This clause has a function symbol with arguments, a number, a distinct object " <>
             "or a defined symbol; its ground instances are not finitely many or not plain."}
    end
  end

  defp function_free?(true), do: true
  defp function_free?({:not, atom}), do: function_free?(atom)

  defp function_free?({:predicate, {:plain, _name}, arguments}),
    do: Enum.all?(arguments, &flat?/1)

  defp function_free?({:equal, left, right}), do: flat?(left) and flat?(right)
  defp function_free?(_literal), do: false

  defp flat?({:variable, _name}), do: true
  defp flat?({:function, {:plain, _name}, []}), do: true
  defp flat?(_term), do: false

  defp universe(clauses) do
    case clauses |> Enum.flat_map(fn {_role, clause} -> terms(clause) end) |> constants() do
      [] -> [{:function, {:plain, fresh(clauses)}, []}]
      constants -> constants
    end
  end

  defp constants(terms), do: terms |> Enum.filter(&match?({:function, _, _}, &1)) |> Enum.uniq()

  defp fresh(clauses) do
    used =
      for {_role, clause} <- clauses,
          {_polarity, {:predicate, {:plain, name}, _arguments}} <-
            Enum.map(clause, &Clause.polarity/1),
          into: MapSet.new(),
          do: name

    ["c"]
    |> Stream.concat(Stream.map(Stream.iterate(1, &(&1 + 1)), &"c#{&1}"))
    |> Enum.find(&(&1 not in used))
  end

  defp instances(clause, universe) do
    variables = for {:variable, _name} = variable <- terms(clause), uniq: true, do: variable

    variables
    |> Enum.reduce([%{}], fn variable, substitutions ->
      Stream.flat_map(substitutions, fn substitution ->
        Stream.map(universe, &Map.put(substitution, variable, &1))
      end)
    end)
    |> Stream.map(fn substitution -> Enum.map(clause, &substitute(&1, substitution)) end)
  end

  defp terms(clause), do: Enum.flat_map(clause, &arguments/1)

  defp arguments(true), do: []
  defp arguments({:not, atom}), do: arguments(atom)
  defp arguments({:predicate, _symbol, arguments}), do: arguments
  defp arguments({:equal, left, right}), do: [left, right]

  defp substitute(true, _substitution), do: true
  defp substitute({:not, atom}, substitution), do: {:not, substitute(atom, substitution)}

  defp substitute({:predicate, symbol, arguments}, substitution),
    do: {:predicate, symbol, Enum.map(arguments, &Map.get(substitution, &1, &1))}

  defp substitute({:equal, left, right}, substitution),
    do: {:equal, Map.get(substitution, left, left), Map.get(substitution, right, right)}
end
