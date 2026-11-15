defmodule Loge.Shex.Messages do
  @moduledoc """
  Reads rudof's errors about a ShExC schema or a shape map into a `Loge.Diagnostic`.

  A syntax error is a chain `Parse error on line L, column C: text`, from the
  construct that failed outward to the token inward, each under `Context:`; lines and
  columns are 1-based and count characters. The diagnostic, `"syntax_error"`, is the
  one character at the innermost position, which is nearest the fault, with the
  innermost text that describes the input: texts `Syntax error: …` name a function of
  rudof's parser, such as `Tag`. The other positions in the chain, with their texts,
  are its related positions.

  Any other error, such as a prefix the source does not declare, a reference to a
  shape the schema does not have, or a negative cycle, is a `"shex_error"` on the
  first line, in rudof's words without the context rudof adds before them.
  """

  alias Loge.{Diagnostic, Range}

  @entry ~r/Parse error on line (\d+), column (\d+): ([^\n]*)/
  @context ~r/\A(?:Schema is malformed\. Error during parsing:\n)?(?:ShEx error: )?(?:Failed to parse [^\n]*? from 'string'(?: in format '\w+')?: )?/

  @doc "The diagnostic for `message`, an error rudof reported reading `source`."
  @spec diagnostic(String.t(), binary()) :: Diagnostic.t()
  def diagnostic(message, source) when is_binary(message) and is_binary(source) do
    case entries(message) do
      [] -> Diagnostic.new("shex_error", :error, Range.new(1), described(message))
      entries -> syntax_error(entries, source)
    end
  end

  @doc "Whether `message` reports a syntax error, which has a position."
  @spec syntax?(String.t()) :: boolean()
  def syntax?(message) when is_binary(message), do: Regex.match?(@entry, message)

  defp entries(message) do
    for [line, column, text] <- Regex.scan(@entry, message, capture: :all_but_first),
        do: {String.to_integer(line), String.to_integer(column), String.trim(text)}
  end

  defp syntax_error(entries, source) do
    {line, column, _text} = List.last(entries)
    described = Enum.reject(entries, fn {_line, _column, text} -> parser?(text) end)
    {_line, _column, text} = List.last(described, List.last(entries))

    related =
      for {at_line, at_column, related} <- Enum.uniq_by(described, &Tuple.delete_at(&1, 2)),
          {at_line, at_column} != {line, column},
          do: {character(source, at_line, at_column), related}

    Diagnostic.new("syntax_error", :error, character(source, line, column), text,
      related: related
    )
  end

  defp parser?("Syntax error: " <> _kind), do: true
  defp parser?(_text), do: false

  defp character(source, line, column),
    do: Range.from_characters(source, line, column: column, end_column: column + 1)

  defp described(message), do: @context |> Regex.replace(message, "") |> String.trim()
end
