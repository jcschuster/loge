defmodule Loge.Egglog.Includes do
  @moduledoc """
  The sources an egglog program includes: the string of each `(include "defs")`
  outside comments and strings. egglog reads such a file from its working directory,
  under the exact name, which is where the engine writes the source of that name
  (`files/1`).

  `names/1` reads a program without egglog, as a cell does on every edit.
  """

  @command ~r/\A\(\s*include\s+"((?:[^"\\]|\\.)*)"\s*\)/

  @doc """
  The names of the sources `source` includes, in order.

      iex> Loge.Egglog.Includes.names(~s|(include "defs")\\n; (include "not")\\n(run 1)|)
      ["defs"]
  """
  @spec names(binary()) :: [String.t()]
  def names(source) when is_binary(source), do: scan(source, [])

  @doc """
  The files to write for `includes`: each source whose name is a word, of letters,
  digits and underscores, as a variable that holds it is named. egglog resolves other
  names on its own.
  """
  @spec files(Loge.Language.includes()) :: [{String.t(), iodata()}]
  def files(includes) when is_map(includes) do
    for {name, input} <- includes, name =~ ~r/\A\w+\z/u, do: {name, Loge.Input.to_iodata(input)}
  end

  defp scan(<<>>, names), do: Enum.reverse(names)
  defp scan(<<?;, rest::binary>>, names), do: rest |> after_match("\n") |> scan(names)
  defp scan(<<?", rest::binary>>, names), do: rest |> after_string() |> scan(names)

  defp scan(<<?(, _::binary>> = source, names) do
    case Regex.run(@command, source, return: :index) do
      [{0, length}, {start, size}] ->
        scan(binary_slice(source, length..-1//1), [binary_part(source, start, size) | names])

      nil ->
        scan(binary_slice(source, 1..-1//1), names)
    end
  end

  defp scan(<<_, rest::binary>>, names), do: scan(rest, names)

  defp after_string(<<?\\, _, rest::binary>>), do: after_string(rest)
  defp after_string(<<?", rest::binary>>), do: rest
  defp after_string(<<_, rest::binary>>), do: after_string(rest)
  defp after_string(<<>>), do: <<>>

  defp after_match(source, pattern) do
    case :binary.match(source, pattern) do
      {at, length} -> binary_part(source, at + length, byte_size(source) - at - length)
      :nomatch -> <<>>
    end
  end
end
