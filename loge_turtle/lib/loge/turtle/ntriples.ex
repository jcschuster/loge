defmodule Loge.Turtle.NTriples do
  @moduledoc """
  Reads N-Triples (https://www.w3.org/TR/n-triples/), the line-based RDF syntax rudof
  serialises a graph in: a triple per line, every IRI written out and every escape
  resolved.

      iex> Loge.Turtle.NTriples.read("<http://e/a> <http://e/p> \\"x\\"@en .\\n_:b0 <http://e/p> <http://e/a> .\\n")
      {:ok,
       [
         {{:iri, "http://e/a"}, {:iri, "http://e/p"}, {:literal, "x", "http://www.w3.org/1999/02/22-rdf-syntax-ns#langString", "en"}},
         {{:blank, "b0"}, {:iri, "http://e/p"}, {:iri, "http://e/a"}}
       ]}
  """

  @string "http://www.w3.org/2001/XMLSchema#string"
  @language_string "http://www.w3.org/1999/02/22-rdf-syntax-ns#langString"

  @typedoc """
  An RDF term: an IRI, a blank node by its label, or a literal by its lexical form,
  the IRI of its datatype and its language tag, `nil` unless the datatype is
  `rdf:langString`.
  """
  @type node_ ::
          {:iri, String.t()}
          | {:blank, String.t()}
          | {:literal, String.t(), String.t(), String.t() | nil}

  @typedoc "Subject, predicate and object."
  @type triple :: {node_(), node_(), node_()}

  @doc "The triples of `text`, in order; `:error` for text that is not N-Triples."
  @spec read(binary()) :: {:ok, [triple()]} | :error
  def read(text) when is_binary(text) do
    text
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "#")))
    |> Enum.reduce_while({:ok, []}, fn line, {:ok, triples} ->
      case triple(line) do
        {:ok, triple} -> {:cont, {:ok, [triple | triples]}}
        :error -> {:halt, :error}
      end
    end)
    |> then(&with({:ok, triples} <- &1, do: {:ok, Enum.reverse(triples)}))
  end

  defp triple(line) do
    with {:ok, subject, rest} <- term(line),
         {:ok, {:iri, _iri} = predicate, rest} <- term(String.trim_leading(rest)),
         {:ok, object, rest} <- term(String.trim_leading(rest)),
         "." <- String.trim(rest) do
      {:ok, {subject, predicate, object}}
    else
      _other -> :error
    end
  end

  defp term(<<?<, rest::binary>>) do
    with {:ok, iri, rest} <- until(rest, ?>, []), do: {:ok, {:iri, iri}, rest}
  end

  defp term(<<"_:", rest::binary>>) do
    case Regex.run(~r/\A[^\s]*[^\s.]/u, rest) do
      [label] ->
        {:ok, {:blank, label},
         binary_part(rest, byte_size(label), byte_size(rest) - byte_size(label))}

      nil ->
        :error
    end
  end

  defp term(<<?", rest::binary>>) do
    with {:ok, lexical, rest} <- until(rest, ?", []), do: literal(lexical, rest)
  end

  defp term(_text), do: :error

  defp literal(lexical, <<"^^<", rest::binary>>) do
    with {:ok, datatype, rest} <- until(rest, ?>, []),
         do: {:ok, {:literal, lexical, datatype, nil}, rest}
  end

  defp literal(lexical, <<?@, rest::binary>>) do
    case Regex.run(~r/\A[A-Za-z]+(-[A-Za-z0-9]+)*/, rest) do
      [tag | _] ->
        {:ok, {:literal, lexical, @language_string, tag},
         binary_part(rest, byte_size(tag), byte_size(rest) - byte_size(tag))}

      nil ->
        :error
    end
  end

  defp literal(lexical, rest), do: {:ok, {:literal, lexical, @string, nil}, rest}

  defp until(<<closing, rest::binary>>, closing, read),
    do: {:ok, read |> Enum.reverse() |> IO.iodata_to_binary(), rest}

  defp until(<<?\\, ?u, hex::binary-size(4), rest::binary>>, closing, read),
    do: code_point(hex, rest, closing, read)

  defp until(<<?\\, ?U, hex::binary-size(8), rest::binary>>, closing, read),
    do: code_point(hex, rest, closing, read)

  defp until(<<?\\, escaped, rest::binary>>, closing, read) do
    case escaped do
      ?t -> until(rest, closing, ["\t" | read])
      ?b -> until(rest, closing, ["\b" | read])
      ?n -> until(rest, closing, ["\n" | read])
      ?r -> until(rest, closing, ["\r" | read])
      ?f -> until(rest, closing, ["\f" | read])
      char when char in [?", ?', ?\\] -> until(rest, closing, [<<char>> | read])
      _other -> :error
    end
  end

  defp until(<<char::utf8, rest::binary>>, closing, read),
    do: until(rest, closing, [<<char::utf8>> | read])

  defp until(_text, _closing, _read), do: :error

  defp code_point(hex, rest, closing, read) do
    case Integer.parse(hex, 16) do
      {code_point, ""} -> until(rest, closing, [<<code_point::utf8>> | read])
      _other -> :error
    end
  end
end
