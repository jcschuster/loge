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

  defp name({:variable, name}), do: name
  defp name({_kind, {_plain, name}, _arity}), do: name
  defp name(_constant), do: nil

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
