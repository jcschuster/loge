defmodule Loge.Asp.Messages do
  @moduledoc """
  Reads clingo's messages into `Loge.Diagnostic`s.

  A message is a line `<file>:<line>:<column>-[<end line>:]<end column>: <severity>: <text>`
  followed by lines indented by two spaces, which are joined into its text. Lines and
  columns are 1-based and count bytes; the end column is exclusive. A `note` adds a
  related position to the message before it. Other lines, such as clingo's closing
  `*** ERROR` summary, are not messages.

  The code of an error is `"error"`; that of an info or warning is the clingo warning
  class it belongs to, as `--warn` names it: `"atom-undefined"`,
  `"operation-undefined"`, `"file-included"`, `"global-variable"`, or `"other"`.
  """

  alias Loge.{Diagnostic, Range}

  @header ~r/^(.+):(\d+):(\d+)-(?:(\d+):)?(\d+): (error|warning|info|note): (.*)$/

  @doc """
  The diagnostics in clingo's `output` about `source`, which clingo read from `file`.
  A message about another file, such as an included one, is placed on the first line
  and names that file.
  """
  @spec parse(binary(), binary(), Path.t()) :: [Diagnostic.t()]
  def parse(output, source, file) when is_binary(output) and is_binary(source) do
    lines = line_offsets(source)

    output
    |> String.split("\n")
    |> Enum.chunk_while(nil, &entry/2, &close/1)
    |> Enum.reduce([], &attach(&1, &2, source, lines, file))
    |> Enum.reverse()
  end

  defp entry(line, current) do
    case Regex.run(@header, line, capture: :all_but_first) do
      [file, line, column, end_line, end_column, severity, text] ->
        position = {file, int(line), int(column), int(end_line), int(end_column)}
        next = {position, severity, [text]}
        if current, do: {:cont, current, next}, else: {:cont, next}

      nil ->
        continue(line, current)
    end
  end

  defp continue(_line, nil), do: {:cont, nil}

  defp continue("  " <> text, {position, severity, texts}),
    do: {:cont, {position, severity, [String.trim(text) | texts]}}

  defp continue(_line, current), do: {:cont, current, nil}

  defp close(nil), do: {:cont, nil}
  defp close(current), do: {:cont, current, nil}

  defp attach({position, "note", texts}, [diagnostic | rest], source, lines, file) do
    {range, text} = place(position, text(texts), source, lines, file)
    [%{diagnostic | related: diagnostic.related ++ [{range, text}]} | rest]
  end

  defp attach({_position, "note", _texts}, [], _source, _lines, _file), do: []

  defp attach({position, severity, texts}, diagnostics, source, lines, file) do
    text = text(texts)
    {range, message} = place(position, text, source, lines, file)
    severity = severity(severity)
    [Diagnostic.new(code(severity, text), severity, range, message) | diagnostics]
  end

  defp text(texts), do: texts |> Enum.reverse() |> Enum.join(" ") |> String.replace_invalid()

  defp place({file, line, column, end_line, end_column}, text, source, lines, file) do
    start = offset(lines, source, line, column)
    stop = max(offset(lines, source, end_line || line, end_column), start)
    {Range.from_offsets(source, start, stop - start), text}
  end

  defp place({other, _line, _column, _end_line, _end_column}, text, _source, _lines, _file),
    do: {Range.new(1), "in '#{other}': " <> text}

  defp line_offsets(source) do
    starts = for {at, 1} <- :binary.matches(source, "\n"), do: at + 1
    List.to_tuple([0 | starts])
  end

  defp offset(lines, source, line, column) when line <= tuple_size(lines),
    do: min(elem(lines, line - 1) + column - 1, byte_size(source))

  defp offset(_lines, source, _line, _column), do: byte_size(source)

  defp severity("error"), do: :error
  defp severity("warning"), do: :warning
  defp severity("info"), do: :info

  defp code(:error, _text), do: "error"
  defp code(_severity, "atom does not occur in any rule head" <> _), do: "atom-undefined"
  defp code(_severity, "no atoms over signature occur in program" <> _), do: "atom-undefined"
  defp code(_severity, "operation undefined" <> _), do: "operation-undefined"
  defp code(_severity, "interval undefined" <> _), do: "operation-undefined"
  defp code(_severity, "already included file" <> _), do: "file-included"

  defp code(_severity, "global variable in tuple of aggregate element" <> _),
    do: "global-variable"

  defp code(_severity, _text), do: "other"

  defp int(""), do: nil
  defp int(digits), do: String.to_integer(digits)
end
