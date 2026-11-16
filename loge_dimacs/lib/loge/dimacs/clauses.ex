defmodule Loge.Dimacs.Clauses do
  @moduledoc """
  Reads the formats whose problem line is `p cnf <variables> <clauses>`: DIMACS CNF,
  and [QDIMACS 1.1](https://www.qbflib.org/qdimacs.html), which puts a prefix of
  quantifier sets before the clauses.

  A clause is a sequence of nonzero literals ended by `0`, spanning lines freely; a
  literal is a variable `n` or its negation `-n`, with `1 <= n <= variables`. A
  quantifier set is `e` or `a`, the variables it binds, and `0`. QDIMACS requires
  the sets before the clauses, no two contiguous sets of the same quantifier, no
  variable bound twice, every bound variable in a clause, and an existential set
  innermost. A variable no set binds is existential in the outermost set.

  Every finding is an `:error` diagnostic; DIMACS CNF reports a quantifier set as one.
  """

  alias Loge.{Diagnostic, Range}
  alias Loge.Dimacs.Text

  @typedoc "The format read: `:cnf` for DIMACS CNF, `:qdimacs` for QDIMACS."
  @type dialect :: :cnf | :qdimacs

  @typedoc "A quantifier set: its quantifier and the variables it binds."
  @type quantifier_set :: {:exists | :forall, [pos_integer()]}

  @typedoc "What a source states; the prefix is `[]` in DIMACS CNF."
  @type t :: %{
          variables: non_neg_integer(),
          prefix: [quantifier_set()],
          clauses: [[integer()]]
        }

  @quantifiers %{"e" => :exists, "a" => :forall}

  @doc "Reads `source` as `dialect`. Returns what it states, or every finding in source order."
  @spec read(binary(), dialect()) :: {:ok, t()} | {:error, [Diagnostic.t()]}
  def read(source, dialect) when is_binary(source) and dialect in [:cnf, :qdimacs] do
    state = %{
      source: source,
      dialect: dialect,
      header: :none,
      open: nil,
      clauses: [],
      count: 0,
      prefix: [],
      bound: %{},
      occurring: MapSet.new(),
      diagnostics: []
    }

    source |> Text.reduce(state, &item/2) |> finish()
  end

  defp item({:problem, text, at}, state), do: header(state, text, at)

  defp item({:token, text, at}, state) do
    state = require_header(state, at, byte_size(text))

    case Text.integer(text) do
      {:ok, 0} -> close(state)
      {:ok, n} -> number(state, n, at, byte_size(text))
      :error -> word(state, text, at)
    end
  end

  defp header(%{header: :none} = state, text, at) do
    with ["p", "cnf", variables, clauses] <- String.split(text),
         {:ok, variables} <- Text.natural(variables),
         {:ok, clauses} <- Text.natural(clauses) do
      %{state | header: {variables, clauses, at, byte_size(text)}}
    else
      _ ->
        state
        |> error(
          "DIMACS002",
          at,
          byte_size(text),
          "Malformed header; expected `p cnf <variables> <clauses>`."
        )
        |> Map.put(:header, :invalid)
    end
  end

  defp header(state, text, at),
    do:
      error(
        state,
        "DIMACS003",
        at,
        byte_size(text),
        "The header must come once, before the clauses."
      )

  defp require_header(%{header: :none} = state, at, length) do
    state
    |> error(
      "DIMACS001",
      at,
      length,
      "Missing `p cnf <variables> <clauses>` header before the clauses."
    )
    |> Map.put(:header, :invalid)
  end

  defp require_header(state, _at, _length), do: state

  defp word(%{open: nil} = state, marker, at) when is_map_key(@quantifiers, marker),
    do: open_set(state, @quantifiers[marker], at)

  defp word(state, text, at),
    do: error(state, "DIMACS004", at, byte_size(text), "`#{text}` is not an integer literal.")

  defp open_set(%{dialect: :cnf} = state, _quantifier, at) do
    state
    |> error("DIMACS008", at, 1, "Quantifier sets belong to QDIMACS; DIMACS CNF has none.")
    |> Map.put(:open, {:skip, at})
  end

  defp open_set(%{count: count} = state, _quantifier, at) when count > 0 do
    state
    |> error("DIMACS010", at, 1, "Quantifier sets come before the clauses.")
    |> Map.put(:open, {:skip, at})
  end

  defp open_set(%{prefix: [{quantifier, _variables, _at} | _]} = state, quantifier, at) do
    state
    |> error(
      "DIMACS011",
      at,
      1,
      "This set has the quantifier of the set before it; merge the two."
    )
    |> Map.put(:open, {:set, quantifier, [], at})
  end

  defp open_set(state, quantifier, at), do: %{state | open: {:set, quantifier, [], at}}

  defp number(%{open: {:skip, _}} = state, _n, _at, _length), do: state

  defp number(%{open: {:set, _, _, _}} = state, n, at, length) when n < 0,
    do:
      error(
        state,
        "DIMACS004",
        at,
        length,
        "`#{n}` is not a variable; a quantifier set binds variables."
      )

  defp number(%{open: {:set, _, _, _}, header: {variables, _, _, _}} = state, n, at, length)
       when n > variables,
       do: check_variable(state, n, at, length)

  defp number(%{open: {:set, quantifier, variables, start}} = state, n, at, length) do
    state =
      case state.bound do
        %{^n => _} -> error(state, "DIMACS012", at, length, "Variable #{n} is bound twice.")
        bound -> %{state | bound: Map.put(bound, n, {at, length})}
      end

    %{state | open: {:set, quantifier, [n | variables], start}}
  end

  defp number(state, n, at, length) do
    state = check_variable(state, n, at, length)

    open =
      case state.open do
        nil -> {:clause, [n], at, at + length}
        {:clause, literals, start, _stop} -> {:clause, [n | literals], start, at + length}
      end

    %{state | open: open, occurring: MapSet.put(state.occurring, abs(n))}
  end

  defp check_variable(%{header: {variables, _, _, _}} = state, n, at, length)
       when abs(n) > variables,
       do:
         error(
           state,
           "DIMACS005",
           at,
           length,
           "Variable #{abs(n)} exceeds the #{variables} the header declares."
         )

  defp check_variable(state, _n, _at, _length), do: state

  defp close(%{open: nil} = state), do: add_clause(state, [])

  defp close(%{open: {:clause, literals, _, _}} = state),
    do: add_clause(state, Enum.reverse(literals))

  defp close(%{open: {:skip, _}} = state), do: %{state | open: nil}

  defp close(%{open: {:set, _quantifier, [], at}} = state) do
    state
    |> error("DIMACS015", at, 1, "A quantifier set binds at least one variable.")
    |> Map.put(:open, nil)
  end

  defp close(%{open: {:set, quantifier, variables, at}} = state),
    do: %{state | open: nil, prefix: [{quantifier, Enum.reverse(variables), at} | state.prefix]}

  defp add_clause(state, clause),
    do: %{state | open: nil, clauses: [clause | state.clauses], count: state.count + 1}

  defp finish(state) do
    state
    |> terminate()
    |> check_count()
    |> check_innermost()
    |> check_occurring()
    |> result()
  end

  defp terminate(%{open: {:clause, _, start, stop}} = state) do
    state
    |> error("DIMACS007", start, stop - start, "Clause not terminated by `0`.")
    |> close()
  end

  defp terminate(%{open: {:set, _, _, at}} = state), do: unterminated_set(state, at)
  defp terminate(%{open: {:skip, at}} = state), do: unterminated_set(state, at)

  defp terminate(state), do: state

  defp unterminated_set(state, at),
    do: %{error(state, "DIMACS007", at, 1, "Quantifier set not terminated by `0`.") | open: nil}

  defp check_count(%{header: {_, clauses, at, length}, count: count} = state)
       when clauses != count,
       do:
         error(
           state,
           "DIMACS006",
           at,
           length,
           "The header declares #{clauses} clauses; found #{count}."
         )

  defp check_count(%{header: :none} = state) do
    diagnostic =
      Diagnostic.new(
        "DIMACS001",
        :error,
        Range.new(1),
        "Missing `p cnf <variables> <clauses>` header."
      )

    %{state | diagnostics: [diagnostic | state.diagnostics]}
  end

  defp check_count(state), do: state

  defp check_innermost(%{prefix: [{:forall, _variables, at} | _]} = state),
    do: error(state, "DIMACS013", at, 1, "The innermost quantifier set must be existential.")

  defp check_innermost(state), do: state

  defp check_occurring(state) do
    state.bound
    |> Enum.reject(fn {variable, _position} -> MapSet.member?(state.occurring, variable) end)
    |> Enum.reduce(state, fn {variable, {at, length}}, state ->
      error(state, "DIMACS014", at, length, "Variable #{variable} is bound but in no clause.")
    end)
  end

  defp result(%{diagnostics: [], header: {variables, _, _, _}} = state) do
    {:ok,
     %{
       variables: variables,
       prefix: state.prefix |> Enum.reverse() |> Enum.map(fn {q, vars, _at} -> {q, vars} end),
       clauses: Enum.reverse(state.clauses)
     }}
  end

  defp result(%{diagnostics: diagnostics}), do: {:error, Text.in_order(diagnostics)}

  defp error(state, code, at, length, message) do
    diagnostic = Text.error(state.source, code, at, length, message)
    %{state | diagnostics: [diagnostic | state.diagnostics]}
  end
end
