defmodule Loge.Turtle.Engines.Asp do
  @moduledoc """
  An RDF graph as ASP facts `triple(S, P, O).`, as `Loge.Turtle.Facts` describes, every
  word a string, since ASP has no quoted atoms. The status is `:equi_satisfiable`.

      iex> turtle = "@prefix ex: <http://e/> . ex:a ex:p 1 ."
      iex> {:ok, outcome} = Loge.Turtle.Engines.Asp.run(turtle, [])
      iex> outcome.output.text
      "triple(\\"http://e/a\\", \\"http://e/p\\", literal(\\"1\\", \\"http://www.w3.org/2001/XMLSchema#integer\\")).\\n"
  """

  @behaviour Loge.Engine

  alias Loge.Turtle.Facts

  @impl true
  def id, do: :turtle_asp

  @impl true
  def label, do: "Triples as facts"

  @impl true
  def languages, do: [:turtle]

  @impl true
  def task, do: {:translate, :asp, :equi_satisfiable}

  @impl true
  def config_schema, do: []

  @impl true
  def configure(_settings), do: :ok

  @impl true
  def verify(_options), do: :ok

  @impl true
  def roles, do: []

  @impl true
  def controls, do: []

  @impl true
  def run(input, _options), do: Facts.run(id(), :asp, input, &word/1, &fact/2)

  @impl true
  def format_error(reason), do: Facts.format_error(reason)

  defp fact(terms, _position), do: ["triple(", Enum.intersperse(terms, ", "), ").\n"]

  defp word(text),
    do: {:ok, [?", String.replace(text, ["\\", "\"", "\n"], &escape/1), ?"]}

  defp escape("\\"), do: "\\\\"
  defp escape("\""), do: "\\\""
  defp escape("\n"), do: "\\n"
end
