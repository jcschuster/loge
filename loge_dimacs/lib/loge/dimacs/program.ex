defmodule Loge.Dimacs.Program do
  @moduledoc """
  ASP text, in clingo's input language, for propositional clauses: the variable `n` is
  the atom `pn`, chosen freely, and an answer set holds the atoms an assignment makes
  true.
  """

  alias Loge.Dimacs.Cnf

  @doc """
  The choice rule over the atoms of the variables `1..variables`; nothing for none.

      iex> IO.iodata_to_binary(Loge.Dimacs.Program.choice(2))
      "{ p1; p2 }.\\n"
      iex> IO.iodata_to_binary(Loge.Dimacs.Program.choice(0))
      ""
  """
  @spec choice(non_neg_integer()) :: iodata()
  def choice(0), do: []
  def choice(variables), do: ["{ ", Enum.map_intersperse(1..variables, "; ", &atom/1), " }.\n"]

  @doc """
  The rule body that holds exactly when `clause` is false: the complement of each of
  its literals, and `#true` for the empty clause.

      iex> IO.iodata_to_binary(Loge.Dimacs.Program.falsified([1, -2]))
      "not p1, p2"
      iex> IO.iodata_to_binary(Loge.Dimacs.Program.falsified([]))
      "#true"
  """
  @spec falsified(Cnf.clause()) :: iodata()
  def falsified([]), do: "#true"
  def falsified(clause), do: Enum.map_intersperse(clause, ", ", &complement/1)

  defp complement(literal) when literal > 0, do: ["not ", atom(literal)]
  defp complement(literal), do: atom(-literal)

  defp atom(variable), do: [?p, Integer.to_string(variable)]
end
