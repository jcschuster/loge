defmodule Loge.Asp.Aspif do
  @moduledoc """
  Reads a ground program in aspif, the format gringo writes for a solver
  (`clingo --mode=gringo --output=intermediate`), as far as a translation needs it:
  rules and the names of atoms. See "A Tutorial on Hybrid Answer Set Solving with
  clingo", appendix A:
  https://www.cs.uni-potsdam.de/wv/publications/DBLP_conf/rw/KaminskiSW17.pdf

  An atom is a positive integer and a literal an atom or its negation, a negative
  integer.

      iex> Loge.Asp.Aspif.read("asp 1 0 0\\n1 1 1 1 0 0\\n1 0 1 2 0 2 1 -3\\n4 1 p 1 2\\n0\\n")
      {:ok, [{:rule, :choice, [1], {:normal, []}}, {:rule, :disjunction, [2], {:normal, [1, -3]}}, {:output, "p", [2]}]}
  """

  @typedoc "An atom, or its negation as a negative integer."
  @type literal :: integer()

  @typedoc "The body of a rule: a conjunction of literals, or a weight constraint, which is not read further."
  @type body :: {:normal, [literal()]} | :weight

  @typedoc """
  A statement: a rule with the atoms of its head, a disjunction or a choice; the name
  shown for a conjunction of literals, an atom's when it is that one atom; or a
  statement of another type, by the number aspif gives the type.
  """
  @type statement ::
          {:rule, :disjunction | :choice, [pos_integer()], body()}
          | {:output, String.t(), [literal()]}
          | {:other, pos_integer()}

  @doc "The statements of a program, in order; `:error` for text that is not aspif."
  @spec read(binary()) :: {:ok, [statement()]} | :error
  def read(text) when is_binary(text) do
    with ["asp 1 0 0" <> _tags | lines] <- String.split(text, "\n", trim: true),
         {statements, ["0"]} <- Enum.split(lines, -1) do
      statements(statements, [])
    else
      _other -> :error
    end
  end

  defp statements([], read), do: {:ok, Enum.reverse(read)}

  defp statements([line | lines], read) do
    case statement(line) do
      :error -> :error
      statement -> statements(lines, [statement | read])
    end
  end

  defp statement("4 " <> output) do
    with {length, " " <> rest} <- Integer.parse(output),
         <<name::binary-size(^length), rest::binary>> <- rest,
         {:ok, [count | literals]} <- integers(rest),
         true <- count == length(literals) do
      {:output, name, literals}
    else
      _other -> :error
    end
  end

  defp statement(line) do
    case integers(line) do
      {:ok, [1, head, count | rest]} when head in [0, 1] and length(rest) >= count ->
        {heads, body} = Enum.split(rest, count)
        rule(head, heads, body)

      {:ok, [type | _rest]} when type in 2..10 ->
        {:other, type}

      _other ->
        :error
    end
  end

  defp rule(head, heads, [0, count | literals]) when count == length(literals),
    do: {:rule, head(head), heads, {:normal, literals}}

  defp rule(head, heads, [1 | _weights]), do: {:rule, head(head), heads, :weight}
  defp rule(_head, _heads, _body), do: :error

  defp head(0), do: :disjunction
  defp head(1), do: :choice

  defp integers(text) do
    text
    |> String.split()
    |> Enum.reduce_while({:ok, []}, fn token, {:ok, read} ->
      case Integer.parse(token) do
        {integer, ""} -> {:cont, {:ok, [integer | read]}}
        _other -> {:halt, :error}
      end
    end)
    |> then(&with({:ok, read} <- &1, do: {:ok, Enum.reverse(read)}))
  end
end
