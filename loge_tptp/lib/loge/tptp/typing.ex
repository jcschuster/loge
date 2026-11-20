defmodule Loge.Tptp.Typing do
  @moduledoc """
  What a `type` statement of TF0 declares: a type, or a symbol with the types of its
  arguments and of its result.

      iex> {:ok, statement, []} = Tptp.Parser.statement_from_string("tff(t, type, f: (human * $i) > human).")
      iex> Loge.Tptp.Typing.from_node(statement.formula)
      {:ok, {"f", {:function, [{:plain, "human"}, {:defined, "$i"}], {:plain, "human"}}}}
  """

  alias Loge.Tptp.Formula
  alias Tptp.Node

  @typedoc "A type: a declared one by its word, or `$i`, `$int`, `$rat` or `$real`."
  @type type :: Formula.symbol()

  @typedoc """
  What a name is declared as: a type, a function or constant into a type, or a
  predicate or proposition, which is into `$o`.
  """
  @type t :: :type | {:function, [type()], type()} | {:predicate, [type()]}

  @doc """
  Reads the formula of a `type` statement. A typing outside monomorphic TF0, such as
  one with a type variable, is the error.
  """
  @spec from_node(Node.t()) :: {:ok, {String.t(), t()}} | {:error, Node.t()}
  def from_node(%Node{kind: :tff_atom_typing, children: [%Node{kind: :tff_atom_typing} = inner]}),
    do: from_node(inner)

  def from_node(%Node{kind: :tff_atom_typing, children: [%Node{kind: :constant} = name, type]}),
    do: with({:ok, declared} <- declared(type), do: {:ok, {Node.value(name), declared}})

  def from_node(%Node{} = node), do: {:error, node}

  @doc """
  The types a typing names: those of the arguments, then that of the result.

      iex> Loge.Tptp.Typing.types({:function, [{:plain, "human"}, {:defined, "$int"}], {:plain, "human"}})
      [{:plain, "human"}, {:defined, "$int"}, {:plain, "human"}]
  """
  @spec types(t()) :: [type()]
  def types(:type), do: []
  def types({:function, arguments, result}), do: arguments ++ [result]
  def types({:predicate, arguments}), do: arguments

  defp declared(%Node{kind: :defined_type, text: "$tType"}), do: {:ok, :type}

  defp declared(%Node{kind: :tff_mapping_type, children: [arguments, result]}),
    do: mapping(arguments, result)

  defp declared(%Node{} = result), do: mapping(nil, result)

  defp mapping(arguments, %Node{kind: :defined_type, text: "$o"}),
    do: with({:ok, arguments} <- arguments(arguments), do: {:ok, {:predicate, arguments}})

  defp mapping(arguments, result) do
    with {:ok, arguments} <- arguments(arguments),
         {:ok, result} <- type(result),
         do: {:ok, {:function, arguments, result}}
  end

  defp arguments(nil), do: {:ok, []}

  defp arguments(%Node{} = node) do
    node
    |> factors()
    |> Enum.reduce_while({:ok, []}, fn factor, {:ok, types} ->
      case type(factor) do
        {:ok, type} -> {:cont, {:ok, types ++ [type]}}
        {:error, _node} = error -> {:halt, error}
      end
    end)
  end

  defp factors(%Node{kind: kind, children: children})
       when kind in [:tff_unitary_type, :tff_xprod_type],
       do: Enum.flat_map(children, &factors/1)

  defp factors(%Node{} = leaf), do: [leaf]

  defp type(%Node{kind: :type_constant} = leaf), do: {:ok, {:plain, Node.value(leaf)}}

  defp type(%Node{kind: :defined_type, text: name}) when name in ~w($i $int $rat $real),
    do: {:ok, {:defined, name}}

  defp type(%Node{} = node), do: {:error, node}
end
