defmodule Loge.Sparql.Messages do
  @moduledoc """
  Reads the error of rudof's SPARQL reader into a `Loge.Diagnostic`.

  The reader stops at the first error, and its message ends in `error at L:C: text`,
  1-based, the column counting characters. The position is where the reader could not
  go on, which may lie after the fault, at the end of the query; the diagnostic covers
  the one character there. A message without a position is placed on the first line,
  whole. The code is `"syntax_error"`.
  """

  alias Loge.{Diagnostic, Range}

  @position ~r/error at (\d+):(\d+): (.*)\z/s

  @doc "The diagnostic for `message`, an error rudof reported reading the query `source`."
  @spec diagnostic(String.t(), binary()) :: Diagnostic.t()
  def diagnostic(message, source) when is_binary(message) and is_binary(source) do
    {range, text} =
      case Regex.run(@position, message, capture: :all_but_first) do
        [line, column, text] ->
          [line, column] = Enum.map([line, column], &String.to_integer/1)
          {Range.from_characters(source, line, column: column, end_column: column + 1), text}

        nil ->
          {Range.new(1), message}
      end

    Diagnostic.new("syntax_error", :error, range, text)
  end
end
