defmodule Loge.Tptp.Engines.Fof do
  @moduledoc """
  A problem of clauses in first-order form: each `cnf` statement as the `fof`
  statement of its name and role whose formula is the clause under a universal
  quantifier over its variables. A `fof` statement is restated the same way, a free
  variable being universal there too. Annotations are left out.

  A clause says what its universal closure says, so the status is `:equivalent`.

  A statement that is neither `cnf` nor `fof` is outside the fragment: the outcome is
  `:inappropriate` (`Loge.Tptp.Translation`). `Loge.Tptp.Engines.Untyped` reads TF0.

      iex> {:ok, outcome} = Loge.Tptp.Engines.Fof.run("cnf(a, negated_conjecture, p(X) | ~ q(X, Y)).", [])
      iex> outcome.output.text
      "fof(a, negated_conjecture, ![X, Y]: (p(X) | ~q(X, Y))).\\n"
  """

  @behaviour Loge.Engine

  alias Loge.Tptp.{Formula, Translation}

  @impl true
  def id, do: :fof

  @impl true
  def label, do: "First-order form"

  @impl true
  def languages, do: [:tptp]

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
  def run(input, options) do
    with {:ok, unit} <- Translation.read(input, options) do
      {:ok,
       case Translation.statements(unit, &statement/1) do
         {:ok, statements} -> Translation.translated(id(), :equivalent, :tptp, statements)
         {:inappropriate, diagnostics} -> Translation.inappropriate(id(), diagnostics)
       end}
    end
  end

  @impl true
  def format_error(reason), do: Translation.format_error(reason)

  defp statement(statement) do
    with {:ok, formula} <- Translation.formula(statement),
         do: {:ok, Translation.restated(statement, :fof, Formula.closure(formula))}
  end
end
