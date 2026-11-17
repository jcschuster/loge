defmodule Loge.Tptp.Engines.Thf do
  @moduledoc """
  An untyped first-order problem in TH0, the typed higher-order form.

  Every symbol is declared in a `type` statement named `t1`, `t2`, … past the names
  the problem uses: a function of `n` arguments as `$i > … > $i`, a predicate into
  `$o`, in the order the symbols first occur. A `fof` or `cnf` statement is the `thf`
  statement of its name and role: an application `f(s, t)` is `(f @ s @ t)`, and a
  variable is bound with the type `$i`, a free one by a universal quantifier.
  Annotations are left out.

  The statements say in Henkin semantics what they said in first-order logic, over the
  same symbols, so the status is `:equivalent`.

  Outside the fragment, with the outcome `:inappropriate` (`Loge.Tptp.Translation`): a
  statement that is neither `fof` nor `cnf`; a number, a distinct object and a defined
  or system symbol other than `$true` and `$false`; and a name the problem uses in two
  ways, as a function and a predicate or with two arities, since a symbol of TH0 has
  one type.

      iex> {:ok, outcome} = Loge.Tptp.Engines.Thf.run("fof(a, axiom, ![X]: (p(X, c) => q)).", [])
      iex> String.split(outcome.output.text, "\\n", trim: true)
      [
        "thf(t1, type, p: $i > $i > $o).",
        "thf(t2, type, c: $i).",
        "thf(t3, type, q: $o).",
        "thf(a, axiom, (![X: $i]: ((p @ X @ c) => q)))."
      ]
  """

  @behaviour Loge.Engine

  alias Loge.Tptp.{Formula, Signature, Translation}
  alias Tptp.Node
  alias Tptp.Printer.Canonical

  @impl true
  def id, do: :thf

  @impl true
  def label, do: "Typed higher-order form"

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
       with {:ok, statements} <- Translation.statements(unit, &statement/1),
            uses = statements |> Enum.flat_map(& &1.uses) |> Enum.uniq(),
            symbols = Enum.reject(uses, &match?({:variable, _name}, &1)),
            :ok <- Translation.unambiguous(symbols, "A symbol of TH0 has one type.") do
         Translation.translated(id(), :equivalent, :tptp, [
           declarations(symbols, statements),
           Enum.map(statements, &restated/1)
         ])
       else
         {:inappropriate, diagnostics} -> Translation.inappropriate(id(), diagnostics)
       end}
    end
  end

  @impl true
  def format_error(reason), do: Translation.format_error(reason)

  defp statement(statement) do
    with {:ok, formula} <- Translation.formula(statement),
         formula = Formula.closure(formula),
         uses = Signature.uses(formula),
         nil <- Enum.find_value(uses, &outside/1) do
      {:ok, %{statement: statement, formula: formula, uses: uses}}
    else
      {:outside, _sentence} = outside -> outside
      sentence when is_binary(sentence) -> {:outside, sentence}
    end
  end

  defp outside({:variable, _name}), do: nil
  defp outside({_kind, {:plain, _name}, _arity}), do: nil

  defp outside({_kind, {_defined, name}, _arity}),
    do: "#{name} is not translated; its type is not $i."

  defp outside({_kind, text}), do: "#{text} is not translated; its type is not $i."

  defp declarations(symbols, statements) do
    used = MapSet.new(statements, &Node.value(&1.statement.name))

    names =
      1
      |> Stream.iterate(&(&1 + 1))
      |> Stream.map(&"t#{&1}")
      |> Stream.reject(&(&1 in used))

    symbols
    |> Enum.zip(names)
    |> Enum.map(fn {{kind, {:plain, symbol}, arity}, name} ->
      [
        "thf(",
        name,
        ", type, ",
        Formula.atomic_word(symbol),
        ": ",
        Enum.intersperse(List.duplicate("$i", arity) ++ [result(kind)], " > "),
        ").\n"
      ]
    end)
  end

  defp result(:function), do: "$i"
  defp result(:predicate), do: "$o"

  defp restated(%{statement: statement, formula: formula}) do
    [
      "thf(",
      Canonical.to_iodata(statement.name),
      ", ",
      Canonical.to_iodata(statement.role),
      ", ",
      formula(formula),
      ").\n"
    ]
  end

  defp formula(true), do: "$true"
  defp formula(false), do: "$false"
  defp formula({:predicate, symbol, arguments}), do: term({:function, symbol, arguments})
  defp formula({:equal, left, right}), do: [?(, term(left), " = ", term(right), ?)]
  defp formula({:not, {:equal, left, right}}), do: [?(, term(left), " != ", term(right), ?)]
  defp formula({:not, formula}), do: ["(~ ", formula(formula), ?)]
  defp formula({:and, left, right}), do: binary(left, " & ", right)
  defp formula({:or, left, right}), do: binary(left, " | ", right)
  defp formula({:implies, left, right}), do: binary(left, " => ", right)
  defp formula({:iff, left, right}), do: binary(left, " <=> ", right)
  defp formula({:forall, variables, formula}), do: quantified(?!, variables, formula)
  defp formula({:exists, variables, formula}), do: quantified(??, variables, formula)

  defp binary(left, connective, right), do: [?(, formula(left), connective, formula(right), ?)]

  defp quantified(quantifier, variables, formula) do
    [
      ?(,
      quantifier,
      ?[,
      Enum.map_intersperse(variables, ", ", &[&1, ": $i"]),
      "]: ",
      formula(formula),
      ?)
    ]
  end

  defp term({:variable, name}), do: name
  defp term({:function, {:plain, name}, []}), do: Formula.atomic_word(name)

  defp term({:function, {:plain, name}, arguments}),
    do: [?(, Formula.atomic_word(name), Enum.map(arguments, &[" @ ", term(&1)]), ?)]
end
