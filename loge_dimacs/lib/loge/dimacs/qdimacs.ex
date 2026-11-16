defmodule Loge.Dimacs.Qdimacs do
  @moduledoc """
  A quantified Boolean formula in prenex conjunctive normal form, read from and
  rendered as [QDIMACS 1.1](https://www.qbflib.org/qdimacs.html).

  `parse/1` reads the format as `Loge.Dimacs.Clauses` describes: the `p cnf` header,
  the prefix, a quantifier set per line from the outermost in, then the clauses.
  `Loge.Input` renders a formula the same way.

      iex> Loge.Dimacs.Qdimacs.parse("p cnf 2 1\\na 1 0\\ne 2 0\\n-1 2 0\\n")
      {:ok, %Loge.Dimacs.Qdimacs{variables: 2, prefix: [forall: [1], exists: [2]], clauses: [[-1, 2]]}}
  """

  alias Loge.Diagnostic
  alias Loge.Dimacs.{Clauses, Cnf}

  @enforce_keys [:variables, :prefix, :clauses]
  defstruct @enforce_keys

  @typedoc """
  The quantifier sets from the outermost in, over the clauses over the variables
  `1..variables`. A variable no set binds is existential in the outermost set.
  """
  @type t :: %__MODULE__{
          variables: non_neg_integer(),
          prefix: [Clauses.quantifier_set()],
          clauses: [Cnf.clause()]
        }

  @doc """
  Reads QDIMACS. Returns the formula, or every finding about the source as an
  `:error` diagnostic in source order.
  """
  @spec parse(binary()) :: {:ok, t()} | {:error, [Diagnostic.t()]}
  def parse(source) when is_binary(source) do
    with {:ok, read} <- Clauses.read(source, :qdimacs), do: {:ok, struct!(__MODULE__, read)}
  end

  @doc """
  The formula an input holds: the input itself when it is one, its parsed bytes
  otherwise. A source that does not parse is `{:error, {:invalid_qdimacs, diagnostics}}`.
  """
  @spec from_input(Loge.Input.t()) ::
          {:ok, t()} | {:error, {:invalid_qdimacs, [Diagnostic.t()]}}
  def from_input(%__MODULE__{} = qbf), do: {:ok, qbf}

  def from_input(input) do
    case input |> Loge.Input.to_iodata() |> IO.iodata_to_binary() |> parse() do
      {:ok, qbf} -> {:ok, qbf}
      {:error, diagnostics} -> {:error, {:invalid_qdimacs, diagnostics}}
    end
  end

  defimpl Loge.Input do
    @markers %{exists: "e", forall: "a"}

    def to_iodata(%{variables: variables, prefix: prefix, clauses: clauses}) do
      [
        "p cnf #{variables} #{length(clauses)}\n",
        Enum.map(prefix, fn {quantifier, bound} ->
          [@markers[quantifier], Enum.map(bound, &[?\s, Integer.to_string(&1)]), " 0\n"]
        end)
        | Cnf.clause_lines(clauses)
      ]
    end

    def language(_qbf), do: :qdimacs
  end
end
