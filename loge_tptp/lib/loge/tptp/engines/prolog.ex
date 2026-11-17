defmodule Loge.Tptp.Engines.Prolog do
  @moduledoc """
  Horn clauses without equality as a Prolog program. A clause with one positive literal
  is the rule `head :- body.`, or the fact `head.` when it has no other literal; a
  clause with none is the query `?- body.`, which asks for what the clause denies, and
  the empty clause is `?- true.`. A clause with `$true` holds and is left out.
  Variables, symbols and quoted words are written as TPTP writes them, which Prolog
  reads the same.

  The program's clauses are the input's, so the status is `:equivalent`, and a query
  has an answer from the least Herbrand model exactly when the input is unsatisfiable.
  Prolog's search is depth-first and without occurs check, so a run on the output may
  not end where a prover would. A predicate named as a built-in of the Prolog system is
  refused by that system when the program is consulted.

  A statement that is not `cnf`, a clause with more than one positive literal, with an
  equation, a number, a distinct object or a defined or system symbol are outside the
  fragment: the outcome is `:inappropriate` (`Loge.Tptp.Translation`).

      iex> {:ok, outcome} = Loge.Tptp.Engines.Prolog.run("cnf(a, axiom, p(X) | ~ q(X, 'A')). cnf(b, axiom, q(a, 'A')). cnf(c, negated_conjecture, ~ p(a)).", [])
      iex> outcome.output.text
      "p(X) :- q(X, 'A').\\nq(a, 'A').\\n?- p(a).\\n"
  """

  @behaviour Loge.Engine

  alias Loge.Tptp.{Clause, Formula, Translation}
  alias Tptp.Printer.Canonical

  @impl true
  def id, do: :tptp_prolog

  @impl true
  def label, do: "Horn clauses"

  @impl true
  def languages, do: [:tptp]

  @impl true
  def task, do: {:translate, :prolog, :equivalent}

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

  defp translated(clauses),
    do:
      Translation.translated(
        id(),
        :equivalent,
        :prolog,
        for(clause <- Enum.concat(clauses), do: [clause, ".\n"])
      )

  defp clause(statement) do
    with {:ok, clause} <- Translation.clause(statement) do
      cond do
        true in clause -> {:ok, []}
        message = Enum.find_value(clause, &outside/1) -> {:outside, message}
        true -> horn(Enum.group_by(clause, &polarity/1, &atom/1))
      end
    end
  end

  defp horn(%{positive: [_, _ | _]}),
    do: {:outside, "This clause has more than one positive literal; it is not a Horn clause."}

  defp horn(%{positive: [head]} = literals),
    do: {:ok, [rule(head, Map.get(literals, :negative, []))]}

  defp horn(literals), do: {:ok, [["?- ", body(Map.get(literals, :negative, []))]]}

  defp rule(head, []), do: head
  defp rule(head, body), do: [head, " :- ", body(body)]

  defp body([]), do: "true"
  defp body(atoms), do: Enum.intersperse(atoms, ", ")

  defp polarity(literal), do: literal |> Clause.polarity() |> elem(0)

  defp atom(literal) do
    {_polarity, atom} = Clause.polarity(literal)
    atom |> Formula.to_node() |> Canonical.to_iodata()
  end

  defp outside({:not, atom}), do: outside(atom)

  defp outside({:equal, _left, _right}),
    do: "This clause has an equation; Prolog has no equality but unification."

  defp outside({:predicate, {:plain, _name}, arguments}) do
    if Enum.all?(arguments, &plain?/1),
      do: nil,
      else:
        "This clause has a number, a distinct object or a defined symbol, which Prolog reads otherwise."
  end

  defp outside({:predicate, _symbol, _arguments}),
    do: "This clause has a defined predicate, which Prolog does not have."

  defp plain?({:variable, _name}), do: true
  defp plain?({:function, {:plain, _name}, arguments}), do: Enum.all?(arguments, &plain?/1)
  defp plain?(_term), do: false
end
