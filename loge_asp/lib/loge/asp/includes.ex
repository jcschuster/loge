defmodule Loge.Asp.Includes do
  @moduledoc """
  The sources an ASP program includes: the string of each `#include "defs".` outside
  comments and strings. clingo reads such a file beside the file naming it, under the
  exact name, which is where the lint and the engine write the source of that name
  (`files/1`). `#include <name>.` names a file of clingo's own and is not one.

  `names/1` reads a program without clingo, as a cell does on every edit.
  """

  @directive ~r/\A\s*"((?:[^"\\\n]|\\.)*)"\s*\./

  @doc """
  The names of the sources `source` includes, in order.

      iex> Loge.Asp.Includes.names(~s|#include "defs".\\n% #include "not".\\na :- b.|)
      ["defs"]
  """
  @spec names(binary()) :: [String.t()]
  def names(source) when is_binary(source), do: scan(source, [])

  @doc """
  The files to write beside a program for `includes`: each source whose name is a word,
  of letters, digits and underscores, as a variable that holds it is named. clingo
  resolves other names on its own.
  """
  @spec files(Loge.Language.includes()) :: [{String.t(), iodata()}]
  def files(includes) when is_map(includes) do
    for {name, input} <- includes, name =~ ~r/\A\w+\z/u, do: {name, Loge.Input.to_iodata(input)}
  end

  defp scan(<<>>, names), do: Enum.reverse(names)
  defp scan(<<"%*", rest::binary>>, names), do: rest |> after_match("*%") |> scan(names)
  defp scan(<<?%, rest::binary>>, names), do: rest |> after_match("\n") |> scan(names)
  defp scan(<<?", rest::binary>>, names), do: rest |> after_string() |> scan(names)

  defp scan(<<"#include", rest::binary>>, names) do
    case Regex.run(@directive, rest, return: :index) do
      [{0, length}, {start, size}] ->
        scan(binary_slice(rest, length..-1//1), [binary_part(rest, start, size) | names])

      nil ->
        scan(rest, names)
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
