defmodule Loge.Tptp.Engines.Thf do
  @moduledoc """
  A first-order problem, untyped (`fof`, `cnf`) or in monomorphic TF0 (`tff`), in TH0,
  the typed higher-order form.

  A `type` statement is the `thf` statement of its name with the typing curried,
  `f: (a * b) > c` as `f: a > b > c`. Every other symbol is declared in a `type`
  statement named `t1`, `t2`, … past the names the problem uses: a function of `n`
  arguments as `$i > … > $i`, a predicate into `$o`, in the order the symbols first
  occur. Another statement is the `thf` statement of its name and role: an application
  `f(s, t)` is `(f @ s @ t)`, and a variable is bound with its type, `$i` where it has
  none, a free one by a universal quantifier. Annotations are left out.

  The statements say in Henkin semantics what they said in first-order logic, over the
  same symbols, so the status is `:equivalent`. The problem is taken to be well-typed.

  Outside the fragment, with the outcome `:inappropriate` (`Loge.Tptp.Translation`): a
  statement of another TPTP language; a typing that is not monomorphic over declared
  types and `$i`; a number, a distinct object and a defined or system symbol other
  than `$true` and `$false`; and a name the problem uses in two ways, as a function
  and a predicate or with two arities, since a symbol of TH0 has one type.

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
            :ok <- Translation.unambiguous(unit, &symbols/1, "A symbol of TH0 has one type.") do
         Translation.translated(id(), :equivalent, :tptp, problem(statements))
       else
         {:inappropriate, diagnostics} -> Translation.inappropriate(id(), diagnostics)
       end}
    end
  end

  @impl true
  def format_error(reason), do: Translation.format_error(reason)

  defp statement(statement) do
    with {:ok, {:formula, formula}} <- Translation.typed(statement, ["$i"]),
         uses = Signature.uses(formula),
         nil <- Enum.find_value(uses, &outside/1) do
      {:ok, %{statement: statement, formula: formula, uses: uses}}
    else
      {:ok, {:typing, name, declared}} ->
        {:ok, %{statement: statement, typing: {name, declared}, uses: []}}

      {:outside, _sentence} = outside ->
        outside

      sentence when is_binary(sentence) ->
        {:outside, sentence}
    end
  end

  defp symbols(statement) do
    case statement(statement) do
      {:ok, %{uses: uses}} -> Enum.reject(uses, &match?({:variable, _name}, &1))
      {:outside, _sentence} -> []
    end
  end

  defp outside({:variable, _name}), do: nil
  defp outside({_kind, {:plain, _name}, _arity}), do: nil

  defp outside({_kind, {_defined, name}, _arity}),
    do: "#{name} is not translated; its type is not $i."

  defp outside({_kind, text}), do: "#{text} is not translated; its type is not $i."

  defp problem(statements) do
    declared = for %{typing: {name, _declared}} <- statements, into: MapSet.new(), do: name
    used = MapSet.new(statements, &Node.value(&1.statement.name))

    names =
      1
      |> Stream.iterate(&(&1 + 1))
      |> Stream.map(&"t#{&1}")
      |> Stream.reject(&(&1 in used))

    undeclared =
      for %{uses: uses} <- statements,
          {kind, {:plain, name}, arity} when kind in [:predicate, :function] <- uses,
          name not in declared,
          uniq: true,
          do: {name, List.duplicate("$i", arity) ++ [result(kind)]}

    {typings, formulas} = Enum.split_with(statements, &is_map_key(&1, :typing))

    [
      Enum.map(typings, &restated/1),
      undeclared
      |> Enum.zip(names)
      |> Enum.map(fn {{symbol, types}, name} -> typing(name, symbol, types) end),
      Enum.map(formulas, &restated/1)
    ]
  end

  defp typing(name, symbol, types) do
    [
      "thf(",
      name,
      ", type, ",
      Formula.atomic_word(symbol),
      ": ",
      Enum.intersperse(types, " > "),
      ").\n"
    ]
  end

  defp result(:function), do: "$i"
  defp result(:predicate), do: "$o"

  defp curried(:type), do: ["$tType"]
  defp curried({:function, arguments, result}), do: Enum.map(arguments ++ [result], &type/1)
  defp curried({:predicate, arguments}), do: Enum.map(arguments, &type/1) ++ ["$o"]

  defp type({:defined, name}), do: name
  defp type({:plain, name}), do: Formula.atomic_word(name)

  defp restated(%{statement: statement, typing: {symbol, declared}}),
    do: typing(Canonical.to_iodata(statement.name), symbol, curried(declared))

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
      Enum.map_intersperse(
        variables,
        ", ",
        &[Signature.bound_name(&1), ": ", type(Signature.type(&1))]
      ),
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
