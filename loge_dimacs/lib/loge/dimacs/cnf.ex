defmodule Loge.Dimacs.Cnf do
  @moduledoc """
  A propositional formula in conjunctive normal form, read from and rendered as
  DIMACS CNF.

  `parse/1` reads the format of the SAT competitions: lines starting with `c` are
  comments, one `p cnf <variables> <clauses>` header precedes the clauses, and each
  clause is a sequence of nonzero literals terminated by `0`, spanning lines freely.
  A literal is a variable `n` or its negation `-n`, with `1 <= n <= variables`.
  `Loge.Input` renders a formula as DIMACS CNF with one clause per line.

      iex> Loge.Dimacs.Cnf.parse("c two clauses\\np cnf 2 2\\n1 -2 0\\n2 0\\n")
      {:ok, %Loge.Dimacs.Cnf{variables: 2, clauses: [[1, -2], [2]]}}
  """

  alias Loge.{Diagnostic, Range}

  @enforce_keys [:variables, :clauses]
  defstruct @enforce_keys

  @typedoc "A variable `n` as `n`, its negation as `-n`; never `0`."
  @type literal :: integer()

  @typedoc "A disjunction of literals; `[]` is false."
  @type clause :: [literal()]

  @typedoc "A conjunction of clauses over the variables `1..variables`."
  @type t :: %__MODULE__{variables: non_neg_integer(), clauses: [clause()]}

  @blank ~c" \t\r"

  @doc """
  Reads DIMACS CNF. Returns the formula, or every finding about the source as an
  `:error` diagnostic in source order.
  """
  @spec parse(binary()) :: {:ok, t()} | {:error, [Diagnostic.t()]}
  def parse(source) when is_binary(source) do
    state = %{
      source: source,
      header: :none,
      clause: [],
      clause_span: nil,
      clauses: [],
      count: 0,
      diagnostics: []
    }

    source |> line(0, state) |> finish()
  end

  @doc """
  The formula an input holds: the input itself when it is one, its parsed bytes
  otherwise. A source that does not parse is `{:error, {:invalid_cnf, diagnostics}}`.
  """
  @spec from_input(Loge.Input.t()) :: {:ok, t()} | {:error, {:invalid_cnf, [Diagnostic.t()]}}
  def from_input(%__MODULE__{} = cnf), do: {:ok, cnf}

  def from_input(input) do
    case input |> Loge.Input.to_iodata() |> IO.iodata_to_binary() |> parse() do
      {:ok, cnf} -> {:ok, cnf}
      {:error, diagnostics} -> {:error, {:invalid_cnf, diagnostics}}
    end
  end

  defp line(<<char, rest::binary>>, at, state) when char in @blank, do: line(rest, at + 1, state)
  defp line(<<?c, rest::binary>>, at, state), do: comment(rest, at + 1, state)
  defp line(<<?p, _::binary>> = rest, at, state), do: header(rest, at, state)
  defp line(rest, at, state), do: tokens(rest, at, state)

  defp comment(<<?\n, rest::binary>>, at, state), do: line(rest, at + 1, state)
  defp comment(<<_, rest::binary>>, at, state), do: comment(rest, at + 1, state)
  defp comment(<<>>, _at, state), do: state

  defp header(rest, at, state) do
    length = line_length(rest, 0)
    <<_::binary-size(^length), rest::binary>> = rest
    text = state.source |> binary_part(at, length) |> String.trim_trailing()
    tokens(rest, at + length, read_header(text, at, state))
  end

  defp read_header(text, at, %{header: :none} = state) do
    with ["p", "cnf", variables, clauses] <- String.split(text),
         {:ok, variables} <- natural(variables),
         {:ok, clauses} <- natural(clauses) do
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

  defp read_header(text, at, state),
    do:
      error(
        state,
        "DIMACS003",
        at,
        byte_size(text),
        "The header must come once, before the clauses."
      )

  defp tokens(<<char, rest::binary>>, at, state) when char in @blank,
    do: tokens(rest, at + 1, state)

  defp tokens(<<?\n, rest::binary>>, at, state), do: line(rest, at + 1, state)
  defp tokens(<<>>, _at, state), do: state

  defp tokens(rest, at, state) do
    length = token_length(rest, 0)
    <<_::binary-size(^length), rest::binary>> = rest
    token = binary_part(state.source, at, length)
    tokens(rest, at + length, state |> require_header(at, length) |> literal(token, at))
  end

  defp line_length(<<char, rest::binary>>, length) when char != ?\n,
    do: line_length(rest, length + 1)

  defp line_length(_rest, length), do: length

  defp token_length(<<char, rest::binary>>, length) when char not in [?\n | @blank],
    do: token_length(rest, length + 1)

  defp token_length(_rest, length), do: length

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

  defp literal(state, token, at) do
    case integer(token) do
      {:ok, 0} ->
        close_clause(state)

      {:ok, literal} ->
        state
        |> check_variable(literal, at, byte_size(token))
        |> add(literal, at, byte_size(token))

      :error ->
        error(state, "DIMACS004", at, byte_size(token), "`#{token}` is not an integer literal.")
    end
  end

  defp check_variable(%{header: {variables, _, _, _}} = state, literal, at, length)
       when abs(literal) > variables,
       do:
         error(
           state,
           "DIMACS005",
           at,
           length,
           "Variable #{abs(literal)} exceeds the #{variables} the header declares."
         )

  defp check_variable(state, _literal, _at, _length), do: state

  defp add(%{clause_span: nil} = state, literal, at, length),
    do: %{state | clause: [literal], clause_span: {at, at + length}}

  defp add(%{clause_span: {start, _}} = state, literal, at, length),
    do: %{state | clause: [literal | state.clause], clause_span: {start, at + length}}

  defp close_clause(state) do
    %{
      state
      | clauses: [Enum.reverse(state.clause) | state.clauses],
        clause: [],
        clause_span: nil,
        count: state.count + 1
    }
  end

  defp finish(state) do
    state
    |> terminate()
    |> check_count()
    |> result()
  end

  defp terminate(%{clause_span: nil} = state), do: state

  defp terminate(%{clause_span: {start, stop}} = state) do
    state
    |> error("DIMACS007", start, stop - start, "Clause not terminated by `0`.")
    |> close_clause()
  end

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

  defp result(%{diagnostics: [], header: {variables, _, _, _}} = state),
    do: {:ok, %__MODULE__{variables: variables, clauses: Enum.reverse(state.clauses)}}

  defp result(%{diagnostics: diagnostics}),
    do: {:error, Enum.sort_by(diagnostics, &{&1.range.line, &1.range.column || 0})}

  defp error(state, code, at, length, message) do
    range = Range.from_offsets(state.source, at, length)
    %{state | diagnostics: [Diagnostic.new(code, :error, range, message) | state.diagnostics]}
  end

  defp integer("-" <> digits) do
    case natural(digits) do
      {:ok, variable} when variable > 0 -> {:ok, -variable}
      _ -> :error
    end
  end

  defp integer(digits), do: natural(digits)

  defp natural("0"), do: {:ok, 0}

  defp natural(<<digit, _::binary>> = digits) when digit in ?1..?9 do
    case Integer.parse(digits) do
      {natural, ""} -> {:ok, natural}
      _ -> :error
    end
  end

  defp natural(_text), do: :error

  defimpl Loge.Input do
    def to_iodata(%{variables: variables, clauses: clauses}) do
      [
        "p cnf #{variables} #{length(clauses)}\n"
        | Enum.map(clauses, fn clause ->
            Enum.map(clause, &[Integer.to_string(&1), ?\s]) ++ ["0\n"]
          end)
      ]
    end

    def language(_cnf), do: :dimacs
  end
end
