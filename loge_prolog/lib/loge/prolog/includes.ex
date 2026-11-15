defmodule Loge.Prolog.Includes do
  @moduledoc """
  The sources a Prolog program includes, named by atoms in its directives: each
  element of `:- [defs, …].` that is an atom, and the atom of `:- include(defs).`,
  `:- consult(defs).` and `:- ensure_loaded(defs).`. `swipl` resolves such a name to
  `defs.pl` beside the file naming it, which is where a run writes the source of that
  name (`Loge.Prolog.Swipl.consult/4`).

  `names/1` reads a program without `swipl`, as a cell does on every edit: it splits
  the program into terms at their full stops and skips comments, strings and quoted
  atoms.
  """

  @layout [?\s, ?\t, ?\n, ?\r, ?\f, ?\v]
  @symbol ~c"+-*/\\^<>=~:.?@#&$"
  @punctuation ~c"()[]{},|"
  @loaders ["include", "consult", "ensure_loaded"]

  @doc """
  The names of the sources `source` includes, in order.

      iex> Loge.Prolog.Includes.names(":- [defs, library(lists)].\\n:- include(facts).")
      ["defs", "facts"]
  """
  @spec names(binary()) :: [String.t()]
  def names(source) when is_binary(source), do: scan(source, [], [])

  defp scan(<<>>, _term, names), do: Enum.reverse(names)
  defp scan(<<?%, rest::binary>>, term, names), do: rest |> after_match("\n") |> scan(term, names)

  defp scan(<<"/*", rest::binary>>, term, names),
    do: rest |> after_match("*/") |> scan(term, names)

  defp scan(<<"0'\\", _, rest::binary>>, term, names), do: scan(rest, [:other | term], names)
  defp scan(<<"0'''", rest::binary>>, term, names), do: scan(rest, [:other | term], names)
  defp scan(<<"0'", _::utf8, rest::binary>>, term, names), do: scan(rest, [:other | term], names)

  defp scan(<<quote, rest::binary>>, term, names) when quote in [?", ?`] do
    {_text, rest} = quoted(rest, quote)
    scan(rest, [:other | term], names)
  end

  defp scan(<<?', rest::binary>>, term, names) do
    {text, rest} = quoted(rest, ?')
    scan(rest, [{:atom, String.replace(text, "''", "'")} | term], names)
  end

  defp scan(<<char, _::binary>> = source, term, names) when char in @symbol do
    {symbol, rest} = take(source, &(&1 in @symbol))

    if symbol == "." and full_stop?(rest),
      do: scan(rest, [], Enum.reverse(included(Enum.reverse(term)), names)),
      else: scan(rest, [{:atom, symbol} | term], names)
  end

  defp scan(<<char, rest::binary>>, term, names) when char in @punctuation,
    do: scan(rest, [{:punctuation, char} | term], names)

  defp scan(<<char, rest::binary>>, term, names) when char in @layout,
    do: scan(rest, term, names)

  defp scan(<<char::utf8, _::binary>> = source, term, names)
       when char in ?A..?Z or char in ?0..?9 or char == ?_ do
    {_word, rest} = take(source, &alphanumeric?/1)
    scan(rest, [:other | term], names)
  end

  defp scan(<<char::utf8, _::binary>> = source, term, names) when char in ?a..?z or char > 127 do
    {word, rest} = take(source, &alphanumeric?/1)
    scan(rest, [{:atom, word} | term], names)
  end

  defp scan(<<_, rest::binary>>, term, names), do: scan(rest, [:other | term], names)

  defp included([{:atom, ":-"}, {:punctuation, ?[} | list]),
    do: for([{:atom, name}] <- elements(list, 0, [], []), do: name)

  defp included([
         {:atom, ":-"},
         {:atom, loader},
         {:punctuation, ?(},
         {:atom, name},
         {:punctuation, ?)}
       ])
       when loader in @loaders,
       do: [name]

  defp included(_tokens), do: []

  defp elements([{:punctuation, ?]} | _], 0, element, elements),
    do: Enum.reverse([Enum.reverse(element) | elements])

  defp elements([{:punctuation, ?,} | rest], 0, element, elements),
    do: elements(rest, 0, [], [Enum.reverse(element) | elements])

  defp elements([{:punctuation, char} = token | rest], depth, element, elements)
       when char in ~c"([{",
       do: elements(rest, depth + 1, [token | element], elements)

  defp elements([{:punctuation, char} = token | rest], depth, element, elements)
       when char in ~c")]}",
       do: elements(rest, depth - 1, [token | element], elements)

  defp elements([token | rest], depth, element, elements),
    do: elements(rest, depth, [token | element], elements)

  defp elements([], _depth, _element, _elements), do: []

  defp full_stop?(<<>>), do: true
  defp full_stop?(<<char, _::binary>>), do: char in @layout or char == ?%

  defp alphanumeric?(char),
    do: char in ?a..?z or char in ?A..?Z or char in ?0..?9 or char == ?_ or char > 127

  defp take(source, keep?, size \\ 0) do
    case source do
      <<_::binary-size(^size), char::utf8, _::binary>> ->
        if keep?.(char),
          do: take(source, keep?, size + byte_size(<<char::utf8>>)),
          else: split(source, size)

      _shorter ->
        split(source, size)
    end
  end

  defp quoted(source, quote, size \\ 0) do
    case source do
      <<_::binary-size(^size), ^quote, ^quote, _::binary>> -> quoted(source, quote, size + 2)
      <<text::binary-size(^size), ^quote, rest::binary>> -> {text, rest}
      <<_::binary-size(^size), ?\\, _, _::binary>> -> quoted(source, quote, size + 2)
      <<_::binary-size(^size), _, _::binary>> -> quoted(source, quote, size + 1)
      _unterminated -> {source, <<>>}
    end
  end

  defp split(source, size),
    do: {binary_part(source, 0, size), binary_part(source, size, byte_size(source) - size)}

  defp after_match(source, pattern) do
    case :binary.match(source, pattern) do
      {at, length} -> binary_part(source, at + length, byte_size(source) - at - length)
      :nomatch -> <<>>
    end
  end
end
