defmodule Loge.Turtle.Engines.Prolog do
  @moduledoc """
  An RDF graph as Prolog facts `triple(S, P, O).`, as `Loge.Turtle.Facts` describes,
  every word a quoted atom. The status is `:equi_satisfiable`.

      iex> turtle = "@prefix ex: <http://e/> . ex:a ex:says 'it\\\\'s'@en ."
      iex> {:ok, outcome} = Loge.Turtle.Engines.Prolog.run(turtle, [])
      iex> outcome.output.text
      "triple('http://e/a', 'http://e/says', literal('it\\\\'s', 'http://www.w3.org/1999/02/22-rdf-syntax-ns#langString', 'en')).\\n"
  """

  @behaviour Loge.Engine

  alias Loge.Turtle.Facts

  @impl true
  def id, do: :turtle_prolog

  @impl true
  def label, do: "Triples as facts"

  @impl true
  def languages, do: [:turtle]

  @impl true
  def task, do: {:translate, :prolog, :equi_satisfiable}

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
  def run(input, _options), do: Facts.run(id(), :prolog, input, &word/1, &fact/2)

  @impl true
  def format_error(reason), do: Facts.format_error(reason)

  defp fact(terms, _position), do: ["triple(", Enum.intersperse(terms, ", "), ").\n"]

  defp word(text) do
    {:ok, [?', String.replace(text, ["\\", "'", "\n", "\t", "\r"], &escape/1), ?']}
  end

  defp escape("\\"), do: "\\\\"
  defp escape("'"), do: "\\'"
  defp escape("\n"), do: "\\n"
  defp escape("\t"), do: "\\t"
  defp escape("\r"), do: "\\r"
end
