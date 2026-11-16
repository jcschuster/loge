defmodule Loge.Dimacs.Wcnf do
  @moduledoc """
  A weighted partial MaxSAT instance: hard clauses, which must hold, and soft clauses
  with weights, read from and rendered as WCNF.

  `parse/1` reads both formats of the MaxSAT Evaluations. In the format of
  [2022 on](https://maxsat-evaluations.github.io/2023/rules.html) there is no
  problem line, a hard clause starts with `h` and a soft one with its weight. In the
  [format before](https://maxsat-evaluations.github.io/2021/rules.html) the problem
  line `p wcnf <variables> <clauses> <top>` comes first and every clause starts with
  its weight, a weight of at least `top` making it hard. A weight is a positive
  integer below 2^63; the rest of a clause is as in DIMACS CNF. `Loge.Input`
  renders the format before, the one clasp reads, with `top` one more than the sum of
  the soft weights.

  An optimum is an assignment that satisfies the hard clauses and whose cost, the sum
  of the weights of the soft clauses it falsifies, is least.

      iex> Loge.Dimacs.Wcnf.parse("h 1 2 0\\n3 -1 0\\n")
      {:ok, %Loge.Dimacs.Wcnf{variables: 2, hard: [[1, 2]], soft: [{3, [-1]}]}}
  """

  alias Loge.Diagnostic
  alias Loge.Dimacs.{Cnf, Text}

  @enforce_keys [:variables, :hard, :soft]
  defstruct @enforce_keys

  @typedoc "The weight of a soft clause."
  @type weight :: pos_integer()

  @typedoc "Hard and soft clauses over the variables `1..variables`."
  @type t :: %__MODULE__{
          variables: non_neg_integer(),
          hard: [Cnf.clause()],
          soft: [{weight(), Cnf.clause()}]
        }

  @weight_bound Bitwise.bsl(1, 63)

  @doc """
  Reads WCNF in either format. Returns the instance, or every finding about the source
  as an `:error` diagnostic in source order.
  """
  @spec parse(binary()) :: {:ok, t()} | {:error, [Diagnostic.t()]}
  def parse(source) when is_binary(source) do
    state = %{
      source: source,
      header: :none,
      started: false,
      open: nil,
      hard: [],
      soft: [],
      count: 0,
      variables: 0,
      diagnostics: []
    }

    source |> Text.reduce(state, &item/2) |> finish()
  end

  @doc """
  The instance an input holds: the input itself when it is one, its parsed bytes
  otherwise. A source that does not parse is `{:error, {:invalid_wcnf, diagnostics}}`.
  """
  @spec from_input(Loge.Input.t()) :: {:ok, t()} | {:error, {:invalid_wcnf, [Diagnostic.t()]}}
  def from_input(%__MODULE__{} = wcnf), do: {:ok, wcnf}

  def from_input(input) do
    case input |> Loge.Input.to_iodata() |> IO.iodata_to_binary() |> parse() do
      {:ok, wcnf} -> {:ok, wcnf}
      {:error, diagnostics} -> {:error, {:invalid_wcnf, diagnostics}}
    end
  end

  defp item({:problem, text, at}, %{header: :none, started: false} = state) do
    with ["p", "wcnf", variables, clauses, top] <- String.split(text),
         {:ok, variables} <- Text.natural(variables),
         {:ok, clauses} <- Text.natural(clauses),
         {:ok, top} <- weight(top) do
      %{state | header: {variables, clauses, top, at, byte_size(text)}}
    else
      _ ->
        state
        |> error(
          "DIMACS002",
          at,
          byte_size(text),
          "Malformed problem line; expected `p wcnf <variables> <clauses> <top>`, or none."
        )
        |> Map.put(:header, :invalid)
    end
  end

  defp item({:problem, text, at}, state),
    do:
      error(
        state,
        "DIMACS003",
        at,
        byte_size(text),
        "The problem line must come once, before the clauses."
      )

  defp item({:token, text, at}, %{open: nil} = state),
    do: start(%{state | started: true}, text, at)

  defp item({:token, text, at}, state) do
    case Text.integer(text) do
      {:ok, 0} ->
        close(state)

      {:ok, n} ->
        literal(state, n, at, byte_size(text))

      :error ->
        error(state, "DIMACS004", at, byte_size(text), "`#{text}` is not an integer literal.")
    end
  end

  defp start(%{header: {_, _, _, _, _}} = state, "h", at) do
    state
    |> error(
      "DIMACS008",
      at,
      1,
      "`h` marks a hard clause in the format without a problem line; under `p wcnf` a hard clause has the weight top."
    )
    |> open(:hard, at, 1)
  end

  defp start(state, "h", at), do: open(state, :hard, at, 1)

  defp start(state, text, at) do
    case {weight(text), state.header} do
      {{:ok, weight}, {_, _, top, _, _}} when weight >= top ->
        open(state, :hard, at, byte_size(text))

      {{:ok, weight}, _header} ->
        open(state, {:soft, weight}, at, byte_size(text))

      {:error, _header} ->
        state
        |> error(
          "DIMACS004",
          at,
          byte_size(text),
          "`#{text}` is not a weight; a clause starts with `h` or a positive integer below 2^63."
        )
        |> open(:invalid, at, byte_size(text))
    end
  end

  defp open(state, kind, at, length), do: %{state | open: {kind, [], at, at + length}}

  defp literal(%{open: {kind, literals, start, _stop}} = state, n, at, length) do
    state = check_variable(state, n, at, length)

    %{
      state
      | open: {kind, [n | literals], start, at + length},
        variables: max(state.variables, abs(n))
    }
  end

  defp check_variable(%{header: {variables, _, _, _, _}} = state, n, at, length)
       when abs(n) > variables,
       do:
         error(
           state,
           "DIMACS005",
           at,
           length,
           "Variable #{abs(n)} exceeds the #{variables} the problem line declares."
         )

  defp check_variable(state, _n, _at, _length), do: state

  defp close(%{open: {kind, literals, _, _}} = state) do
    clause = Enum.reverse(literals)
    state = %{state | open: nil, count: state.count + 1}

    case kind do
      :hard -> %{state | hard: [clause | state.hard]}
      {:soft, weight} -> %{state | soft: [{weight, clause} | state.soft]}
      :invalid -> state
    end
  end

  defp finish(state) do
    state
    |> terminate()
    |> check_count()
    |> result()
  end

  defp terminate(%{open: {_, _, start, stop}} = state) do
    state
    |> error("DIMACS007", start, stop - start, "Clause not terminated by `0`.")
    |> close()
  end

  defp terminate(state), do: state

  defp check_count(%{header: {_, clauses, _, at, length}, count: count} = state)
       when clauses != count,
       do:
         error(
           state,
           "DIMACS006",
           at,
           length,
           "The problem line declares #{clauses} clauses; found #{count}."
         )

  defp check_count(state), do: state

  defp result(%{diagnostics: []} = state) do
    variables =
      case state.header do
        {variables, _, _, _, _} -> variables
        :none -> state.variables
      end

    {:ok,
     %__MODULE__{
       variables: variables,
       hard: Enum.reverse(state.hard),
       soft: Enum.reverse(state.soft)
     }}
  end

  defp result(%{diagnostics: diagnostics}), do: {:error, Text.in_order(diagnostics)}

  defp weight(text) do
    case Text.natural(text) do
      {:ok, weight} when weight > 0 and weight < @weight_bound -> {:ok, weight}
      _ -> :error
    end
  end

  defp error(state, code, at, length, message) do
    diagnostic = Text.error(state.source, code, at, length, message)
    %{state | diagnostics: [diagnostic | state.diagnostics]}
  end

  defimpl Loge.Input do
    def to_iodata(%{variables: variables, hard: hard, soft: soft}) do
      top = soft |> Enum.map(&elem(&1, 0)) |> Enum.sum() |> Kernel.+(1)

      [
        "p wcnf #{variables} #{length(hard) + length(soft)} #{top}\n",
        weighted(top, hard)
        | Enum.map(soft, fn {weight, clause} -> weighted(weight, [clause]) end)
      ]
    end

    def language(_wcnf), do: :wcnf

    defp weighted(weight, clauses),
      do: Enum.map(Loge.Dimacs.Cnf.clause_lines(clauses), &[Integer.to_string(weight), ?\s | &1])
  end
end
