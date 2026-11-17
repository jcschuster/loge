defmodule Loge.Tptp.Engines.Tff do
  @moduledoc """
  An untyped first-order problem in TF0, the typed first-order form: each `fof` and
  `cnf` statement as the `tff` statement of its name and role, its free variables
  under a universal quantifier. Nothing is declared: in TF0 a variable without a type
  is of type `$i`, and a symbol without a declaration is over `$i`, a predicate into
  `$o`, which is how the untyped forms read them. Annotations are left out.

  The statements say what they said, so the status is `:equivalent`.

  A statement that is neither `fof` nor `cnf` is outside the fragment: the outcome is
  `:inappropriate` (`Loge.Tptp.Translation`).

      iex> {:ok, outcome} = Loge.Tptp.Engines.Tff.run("fof(a, axiom, p(X) => ?[Y]: q(X, Y)).", [])
      iex> outcome.output.text
      "tff(a, axiom, ![X]: (p(X) => ?[Y]: q(X, Y))).\\n"
  """

  @behaviour Loge.Engine

  alias Loge.Tptp.{Formula, Translation}

  @impl true
  def id, do: :tff

  @impl true
  def label, do: "Typed first-order form"

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
         do: {:ok, Translation.restated(statement, :tff, Formula.closure(formula))}
  end
end
