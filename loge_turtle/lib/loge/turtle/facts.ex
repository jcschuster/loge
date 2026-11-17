defmodule Loge.Turtle.Facts do
  @moduledoc """
  What the translations out of Turtle share: a graph as facts `triple(S, P, O)`, one
  per triple, in the order rudof serialises them.

  rudof reads the Turtle and writes it as N-Triples (`Loge.Turtle.NTriples`), so
  prefixes, the base, collections and abbreviations are resolved before a fact is
  written. An engine says how its target writes a word, and whether it can:

    * an IRI is the word of its text;
    * a blank node is the word `_:label`, a name for the thing the graph says exists;
    * a literal is `literal(lexical, datatype)`, both words, or
      `literal(lexical, datatype, language)` for a language-tagged string.

  The facts state the triples of the graph over those words. A blank node says that
  something exists and the facts name it, so the facts entail the graph and both are
  satisfiable: the status is `:equi_satisfiable`. Without blank nodes they say the
  same.
  """

  alias Loge.Outcome
  alias Loge.Turtle.{Messages, NTriples}
  alias Rudof.Session

  @typedoc "How a target writes a word, or the sentence saying why it cannot."
  @type word :: (String.t() -> {:ok, iodata()} | {:outside, String.t()})

  @doc """
  The outcome of `engine` for the Turtle `input`: its triples as facts in `language`,
  each written by `fact` from the words of its subject, predicate and object. Turtle
  that does not read is `{:error, {:invalid_turtle, diagnostics}}`; a word the target
  cannot write makes the outcome `:inappropriate`.
  """
  @spec run(atom(), atom(), Loge.Input.t(), word(), ([iodata()], pos_integer() -> iodata())) ::
          {:ok, Outcome.t()} | {:error, term()}
  def run(engine, language, input, word, fact) do
    turtle = input |> Loge.Input.to_iodata() |> IO.iodata_to_binary()

    with {:ok, triples} <- triples(turtle) do
      written = triples |> Enum.with_index(1) |> Enum.map(&written(&1, word, fact))

      {:ok,
       case for {:outside, sentence} <- written, uniq: true, do: sentence do
         [] -> translated(engine, language, for({:ok, text} <- written, do: text))
         sentences -> inappropriate(engine, sentences)
       end}
    end
  end

  @doc "A sentence describing an error of `run/5`."
  @spec format_error(term()) :: String.t()
  def format_error({:invalid_turtle, diagnostics}) do
    "Invalid Turtle:" <> Enum.map_join(diagnostics, &"\nline #{&1.range.line}: #{&1.message}")
  end

  def format_error({:rudof, message}), do: message
  def format_error(reason), do: inspect(reason, pretty: true, width: 80)

  defp triples(turtle) do
    Session.with_session(fn session ->
      with :ok <- Session.read_data(session, turtle, format: :turtle),
           {:ok, text} <- Session.serialize_data(session, :ntriples),
           {:ok, triples} <- NTriples.read(text) do
        {:ok, triples}
      else
        {:error, %Rudof.Error{kind: :data_error, message: message}} ->
          {:error, {:invalid_turtle, [Messages.diagnostic(message, turtle)]}}

        {:error, %Rudof.Error{message: message}} ->
          {:error, {:rudof, message}}

        :error ->
          {:error, {:rudof, "rudof did not serialise the graph as N-Triples."}}
      end
    end)
  end

  defp written({{subject, predicate, object}, position}, word, fact) do
    terms = Enum.map([subject, predicate, object], &term(&1, word))

    case Enum.find(terms, &match?({:outside, _sentence}, &1)) do
      nil -> {:ok, fact.(for({:ok, term} <- terms, do: term), position)}
      outside -> outside
    end
  end

  defp term({:iri, iri}, word), do: word.(iri)
  defp term({:blank, label}, word), do: word.("_:" <> label)
  defp term({:literal, lexical, datatype, nil}, word), do: literal([lexical, datatype], word)

  defp term({:literal, lexical, datatype, language}, word),
    do: literal([lexical, datatype, language], word)

  defp literal(parts, word) do
    words = Enum.map(parts, word)

    case Enum.find(words, &match?({:outside, _sentence}, &1)) do
      nil -> {:ok, ["literal(", Enum.intersperse(for({:ok, word} <- words, do: word), ", "), ?)]}
      outside -> outside
    end
  end

  defp translated(engine, language, facts) do
    text = IO.iodata_to_binary(facts)

    %Outcome{
      status: :equi_satisfiable,
      problem: :translation,
      raw: text,
      engine: engine,
      output: Loge.source(language, text)
    }
  end

  defp inappropriate(engine, sentences) do
    %Outcome{
      status: :inappropriate,
      problem: :translation,
      raw: "",
      engine: engine,
      views: [
        {:diagnostics,
         Enum.map(sentences, &Loge.Diagnostic.new("fragment", :error, Loge.Range.new(1), &1))}
      ]
    }
  end
end
