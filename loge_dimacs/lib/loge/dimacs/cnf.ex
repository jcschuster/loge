defmodule Loge.Dimacs.Cnf do
  @moduledoc """
  A propositional formula in conjunctive normal form, read from and rendered as
  DIMACS CNF.

  `parse/1` reads the format of the SAT competitions as `Loge.Dimacs.Clauses`
  describes: lines starting with `c` are comments, one `p cnf <variables> <clauses>`
  header precedes the clauses, and each clause is a sequence of nonzero literals
  terminated by `0`. `Loge.Input` renders a formula as DIMACS CNF with one clause per
  line.

      iex> Loge.Dimacs.Cnf.parse("c two clauses\\np cnf 2 2\\n1 -2 0\\n2 0\\n")
      {:ok, %Loge.Dimacs.Cnf{variables: 2, clauses: [[1, -2], [2]]}}
  """

  alias Loge.Diagnostic
  alias Loge.Dimacs.Clauses

  @enforce_keys [:variables, :clauses]
  defstruct @enforce_keys

  @typedoc "A variable `n` as `n`, its negation as `-n`; never `0`."
  @type literal :: integer()

  @typedoc "A disjunction of literals; `[]` is false."
  @type clause :: [literal()]

  @typedoc "A conjunction of clauses over the variables `1..variables`."
  @type t :: %__MODULE__{variables: non_neg_integer(), clauses: [clause()]}

  @doc """
  Reads DIMACS CNF. Returns the formula, or every finding about the source as an
  `:error` diagnostic in source order.
  """
  @spec parse(binary()) :: {:ok, t()} | {:error, [Diagnostic.t()]}
  def parse(source) when is_binary(source) do
    with {:ok, %{variables: variables, clauses: clauses}} <- Clauses.read(source, :cnf),
         do: {:ok, %__MODULE__{variables: variables, clauses: clauses}}
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

  @doc "The clauses as DIMACS CNF clause lines."
  @spec clause_lines([clause()]) :: iodata()
  def clause_lines(clauses),
    do:
      Enum.map(clauses, fn clause ->
        Enum.map(clause, &[Integer.to_string(&1), ?\s]) ++ ["0\n"]
      end)

  defimpl Loge.Input do
    def to_iodata(%{variables: variables, clauses: clauses}),
      do: ["p cnf #{variables} #{length(clauses)}\n" | Loge.Dimacs.Cnf.clause_lines(clauses)]

    def language(_cnf), do: :dimacs
  end
end
