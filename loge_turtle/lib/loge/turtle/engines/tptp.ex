defmodule Loge.Turtle.Engines.Tptp do
  @moduledoc """
  An RDF graph as TPTP: each triple a statement `cnf(tN, axiom, triple(S, P, O)).`, as
  `Loge.Turtle.Facts` describes, every word a single-quoted atomic word. The status is
  `:equi_satisfiable`.

  A single-quoted word of TPTP is of printable ASCII, so a graph with an IRI, a
  literal or a language tag that has another character is outside the fragment: the
  outcome is `:inappropriate`.

      iex> {:ok, outcome} = Loge.Turtle.Engines.Tptp.run("@prefix ex: <http://e/> . ex:a ex:n 'x' .", [])
      iex> outcome.output.text
      "cnf(t1, axiom, triple('http://e/a', 'http://e/n', literal('x', 'http://www.w3.org/2001/XMLSchema#string'))).\\n"
  """

  @behaviour Loge.Engine

  alias Loge.Turtle.Facts

  @impl true
  def id, do: :turtle_tptp

  @impl true
  def label, do: "Triples as facts"

  @impl true
  def languages, do: [:turtle]

  @impl true
  def task, do: {:translate, :tptp, :equi_satisfiable}

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
  def run(input, _options), do: Facts.run(id(), :tptp, input, &word/1, &fact/2)

  @impl true
  def format_error(reason), do: Facts.format_error(reason)

  defp fact(terms, position) do
    [
      "cnf(t",
      Integer.to_string(position),
      ", axiom, triple(",
      Enum.intersperse(terms, ", "),
      ")).\n"
    ]
  end

  defp word(text) do
    if text =~ ~r/\A[\x20-\x7E]*\z/,
      do: {:ok, [?', String.replace(text, ~r/['\\]/, "\\\\\\0"), ?']},
      else: {:outside, "A TPTP word is of printable ASCII, which #{inspect(text)} is not."}
  end
end
