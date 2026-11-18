defmodule Loge.Tptp.Signature do
  @moduledoc """
  What a formula uses: its variables, its predicate and function symbols with their
  arities, its numbers and distinct objects. A translation into a language that
  declares its symbols reads the declarations off it, and finds the names its target
  cannot tell apart.

      iex> {:ok, statement, []} = Tptp.Parser.statement_from_string("fof(a, axiom, ![X]: p(X, f(c))).")
      iex> {:ok, formula} = Loge.Tptp.Formula.from_node(statement.formula)
      iex> Loge.Tptp.Signature.uses(formula)
      [{:variable, "X"}, {:predicate, {:plain, "p"}, 2}, {:function, {:plain, "f"}, 1}, {:function, {:plain, "c"}, 0}]
  """

  alias Loge.Tptp.Formula

  @typedoc "A use: a variable, a symbol as a predicate or a function of an arity, a number or a distinct object."
  @type use ::
          {:variable, String.t()}
          | {:predicate | :function, Formula.symbol(), non_neg_integer()}
          | {:number, String.t()}
          | {:distinct_object, String.t()}

  @doc "The uses of a formula, each once, in the order they first occur; a bound variable is one."
  @spec uses(Formula.t()) :: [use()]
  def uses(formula), do: formula |> formula() |> Enum.uniq()

  @doc """
  The names among `uses` that stand for two things: a variable and a symbol, a
  predicate and a function, or a symbol of two arities.

      iex> Loge.Tptp.Signature.ambiguous([{:predicate, {:plain, "p"}, 1}, {:function, {:plain, "p"}, 0}, {:variable, "X"}])
      ["p"]
  """
  @spec ambiguous([use()]) :: [String.t()]
  def ambiguous(uses) do
    names = for use <- Enum.uniq(uses), name = name(use), do: name
    Enum.uniq(names -- Enum.uniq(names))
  end

  @doc """
  The types of the variables a formula binds, each once, in order; a variable bound
  without a type is of type `$i`.

      iex> Loge.Tptp.Signature.types({:forall, [{"X", {:plain, "human"}}, "Y"], true})
      [{:plain, "human"}, {:defined, "$i"}]
  """
  @spec types(Formula.t()) :: [Formula.symbol()]
  def types(formula), do: formula |> bound_types() |> Enum.uniq()

  @doc "The type of a variable as a quantifier binds it."
  @spec type(Formula.bound()) :: Formula.symbol()
  def type({_name, type}), do: type
  def type(_name), do: {:defined, "$i"}

  @doc "The name of a variable as a quantifier binds it."
  @spec bound_name(Formula.bound()) :: String.t()
  def bound_name({name, _type}), do: name
  def bound_name(name), do: name

  @doc "The names among `uses`: of the variables and of the symbols."
  @spec names([use()]) :: [String.t()]
  def names(uses), do: for(use <- uses, name = name(use), uniq: true, do: name)

  defp name({:variable, name}), do: name
  defp name({_kind, {_plain, name}, _arity}), do: name
  defp name(_constant), do: nil

  defp bound_types({quantifier, variables, formula}) when quantifier in [:forall, :exists],
    do: Enum.map(variables, &type/1) ++ bound_types(formula)

  defp bound_types({:not, formula}), do: bound_types(formula)

  defp bound_types({connective, left, right}) when connective in [:and, :or, :implies, :iff],
    do: bound_types(left) ++ bound_types(right)

  defp bound_types(_atom), do: []

  defp formula(boolean) when is_boolean(boolean), do: []
  defp formula({:not, formula}), do: formula(formula)
  defp formula({:equal, left, right}), do: term(left) ++ term(right)

  defp formula({:predicate, symbol, arguments}),
    do: [{:predicate, symbol, length(arguments)} | Enum.flat_map(arguments, &term/1)]

  defp formula({quantifier, variables, formula}) when quantifier in [:forall, :exists],
    do: Enum.map(variables, &variable/1) ++ formula(formula)

  defp formula({_connective, left, right}), do: formula(left) ++ formula(right)

  defp variable({name, _type}), do: {:variable, name}
  defp variable(name), do: {:variable, name}

  defp term({:function, symbol, arguments}),
    do: [{:function, symbol, length(arguments)} | Enum.flat_map(arguments, &term/1)]

  defp term(other), do: [other]
end
