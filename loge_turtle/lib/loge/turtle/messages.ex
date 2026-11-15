defmodule Loge.Turtle.Messages do
  @moduledoc """
  Reads the error of rudof's Turtle reader into a `Loge.Diagnostic`.

  The reader stops at the first error. Its message ends in
  `Parser error at line L column C: text`, `Parser error at line L between columns C
  and C2: text`, or `Parser error between line L column C and line L2 column C2:
  text`; lines and columns are 1-based, columns count characters, and the end is
  exclusive. A message without a position is placed on the first line, whole. The
  code is `"syntax_error"`.
  """

  alias Loge.{Diagnostic, Range}

  @one ~r/Parser error at line (\d+) column (\d+): (.*)\z/s
  @line ~r/Parser error at line (\d+) between columns (\d+) and (\d+): (.*)\z/s
  @lines ~r/Parser error between line (\d+) column (\d+) and line (\d+) column (\d+): (.*)\z/s

  @doc "The diagnostic for `message`, an error rudof reported reading `source`."
  @spec diagnostic(String.t(), binary()) :: Diagnostic.t()
  def diagnostic(message, source) when is_binary(message) and is_binary(source) do
    {range, text} = place(message, source)
    Diagnostic.new("syntax_error", :error, range, text)
  end

  defp place(message, source) do
    cond do
      match = Regex.run(@lines, message, capture: :all_but_first) ->
        [line, column, end_line, end_column, text] = match
        [line, column, end_line, end_column] = integers([line, column, end_line, end_column])

        {Range.from_characters(source, line,
           column: column,
           end_line: end_line,
           end_column: end_column
         ), text}

      match = Regex.run(@line, message, capture: :all_but_first) ->
        [line, column, end_column, text] = match
        [line, column, end_column] = integers([line, column, end_column])
        {Range.from_characters(source, line, column: column, end_column: end_column), text}

      match = Regex.run(@one, message, capture: :all_but_first) ->
        [line, column, text] = match
        [line, column] = integers([line, column])
        {Range.from_characters(source, line, column: column, end_column: column + 1), text}

      true ->
        {Range.new(1), message}
    end
  end

  defp integers(digits), do: Enum.map(digits, &String.to_integer/1)
end
