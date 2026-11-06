defmodule Loge.Smtlib.Sexp do
  @moduledoc """
  Reads SMT-LIB 2.6 S-expressions, with the byte span of every term.

  Atoms are numerals, decimals, hexadecimals (`#x…`), binaries (`#b…`), strings,
  symbols (simple or `|quoted|`) and keywords (`:name`). A string's value has its
  `""` escapes resolved; a quoted symbol's value is the text between the bars.
  Comments run from `;` to the end of the line. See the SMT-LIB 2.6 standard, §3.1:
  https://smt-lib.org/papers/smt-lib-reference-v2.6-r2021-05-12.pdf

      iex> Loge.Smtlib.Sexp.read("(check-sat)")
      {[{:list, [{:symbol, "check-sat", {1, 9}}], {0, 11}}], []}
  """

  alias Loge.{Diagnostic, Range}

  @typedoc "The byte offset and length of a term in the source."
  @type span :: {non_neg_integer(), non_neg_integer()}

  @typedoc "The kind of an atom."
  @type kind :: :numeral | :decimal | :hexadecimal | :binary | :string | :symbol | :keyword

  @typedoc "A list of terms or an atom, with its span."
  @type t :: {:list, [t()], span()} | {kind(), binary(), span()}

  @delimiters ~c" \t\r\n()\";|"
  @symbol_characters ~c"~!@$%^&*_-+=<>.?/"

  @doc """
  The terms of `source`, and its syntax errors as diagnostics in source order. A list
  left open is closed at the end of the source; a token that is no atom is skipped.
  """
  @spec read(binary()) :: {[t()], [Diagnostic.t()]}
  def read(source) when is_binary(source) do
    {terms, errors} = terms(source, 0, [{[], nil}], [], source)

    diagnostics =
      errors |> Enum.reverse() |> Enum.sort_by(&elem(&1, 1)) |> Enum.map(&diagnostic(&1, source))

    {terms, diagnostics}
  end

  defp terms(<<char, rest::binary>>, at, stack, errors, source) when char in ~c" \t\r\n",
    do: terms(rest, at + 1, stack, errors, source)

  defp terms(<<?;, rest::binary>>, at, stack, errors, source) do
    length = line_length(rest, 0)
    <<_::binary-size(^length), rest::binary>> = rest
    terms(rest, at + 1 + length, stack, errors, source)
  end

  defp terms(<<?(, rest::binary>>, at, stack, errors, source),
    do: terms(rest, at + 1, [{[], at} | stack], errors, source)

  defp terms(<<?), rest::binary>>, at, [{_items, nil}] = stack, errors, source),
    do: terms(rest, at + 1, stack, [{"SMTLIB002", {at, 1}} | errors], source)

  defp terms(<<?), rest::binary>>, at, [{items, start} | stack], errors, source),
    do:
      terms(
        rest,
        at + 1,
        push(stack, {:list, Enum.reverse(items), {start, at + 1 - start}}),
        errors,
        source
      )

  defp terms(<<?", rest::binary>>, at, stack, errors, source) do
    case delimited(rest, ?", 0) do
      {:ok, length} ->
        <<text::binary-size(^length), ?", rest::binary>> = rest
        atom = {:string, String.replace(text, ~S|""|, ~S|"|), {at, length + 2}}
        terms(rest, at + length + 2, push(stack, atom), errors, source)

      :unterminated ->
        finish(stack, [{"SMTLIB003", {at, byte_size(source) - at}} | errors], source)
    end
  end

  defp terms(<<?|, rest::binary>>, at, stack, errors, source) do
    case delimited(rest, ?|, 0) do
      {:ok, length} ->
        <<text::binary-size(^length), ?|, rest::binary>> = rest

        terms(
          rest,
          at + length + 2,
          push(stack, {:symbol, text, {at, length + 2}}),
          errors,
          source
        )

      :unterminated ->
        finish(stack, [{"SMTLIB004", {at, byte_size(source) - at}} | errors], source)
    end
  end

  defp terms(<<>>, _at, stack, errors, source), do: finish(stack, errors, source)

  defp terms(rest, at, stack, errors, source) do
    length = token_length(rest, 0)
    <<token::binary-size(^length), rest::binary>> = rest

    case kind(token) do
      nil -> terms(rest, at + length, stack, [{"SMTLIB005", {at, length}} | errors], source)
      kind -> terms(rest, at + length, push(stack, {kind, token, {at, length}}), errors, source)
    end
  end

  defp push([{items, start} | stack], term), do: [{[term | items], start} | stack]

  defp finish([{items, nil}], errors, _source), do: {Enum.reverse(items), errors}

  defp finish([{items, start} | stack], errors, source) do
    list = {:list, Enum.reverse(items), {start, byte_size(source) - start}}
    finish(push(stack, list), [{"SMTLIB001", {start, 1}} | errors], source)
  end

  defp delimited(<<quote, quote, rest::binary>>, quote, length) when quote == ?",
    do: delimited(rest, quote, length + 2)

  defp delimited(<<quote, _::binary>>, quote, length), do: {:ok, length}
  defp delimited(<<?\\, _::binary>>, ?|, _length), do: :unterminated
  defp delimited(<<_, rest::binary>>, quote, length), do: delimited(rest, quote, length + 1)
  defp delimited(<<>>, _quote, _length), do: :unterminated

  defp line_length(<<?\n, _::binary>>, length), do: length
  defp line_length(<<_, rest::binary>>, length), do: line_length(rest, length + 1)
  defp line_length(<<>>, length), do: length

  defp token_length(<<char, rest::binary>>, length) when char not in @delimiters,
    do: token_length(rest, length + 1)

  defp token_length(_rest, length), do: length

  defp kind("0"), do: :numeral

  defp kind(<<digit, _::binary>> = token) when digit in ?1..?9 do
    cond do
      digits?(token) -> :numeral
      decimal?(token) -> :decimal
      true -> nil
    end
  end

  defp kind("0." <> fraction), do: if(digits?(fraction), do: :decimal)
  defp kind("#x" <> digits), do: if(digits != "" and hexadecimal?(digits), do: :hexadecimal)
  defp kind("#b" <> digits), do: if(digits != "" and binary?(digits), do: :binary)
  defp kind(":" <> name), do: if(name != "" and symbol_characters?(name), do: :keyword)

  defp kind(<<first, _::binary>> = token) when first not in ?0..?9,
    do: if(symbol_characters?(token), do: :symbol)

  defp kind(_token), do: nil

  defp decimal?(token) do
    case String.split(token, ".") do
      [whole, fraction] -> digits?(whole) and digits?(fraction)
      _ -> false
    end
  end

  defp digits?(""), do: false
  defp digits?(text), do: all?(text, &(&1 in ?0..?9))
  defp hexadecimal?(text), do: all?(text, &(&1 in ?0..?9 or &1 in ?a..?f or &1 in ?A..?F))
  defp binary?(text), do: all?(text, &(&1 in ~c"01"))

  defp symbol_characters?(text),
    do: all?(text, &(&1 in ?a..?z or &1 in ?A..?Z or &1 in ?0..?9 or &1 in @symbol_characters))

  defp all?(<<char, rest::binary>>, test), do: test.(char) and all?(rest, test)
  defp all?(<<>>, _test), do: true

  defp diagnostic({code, {offset, length}}, source),
    do: Diagnostic.new(code, :error, Range.from_offsets(source, offset, length), message(code))

  defp message("SMTLIB001"), do: "Unclosed parenthesis."
  defp message("SMTLIB002"), do: "Unmatched closing parenthesis."
  defp message("SMTLIB003"), do: "Unterminated string."
  defp message("SMTLIB004"), do: "Unterminated quoted symbol."
  defp message("SMTLIB005"), do: "Not an SMT-LIB token."
end
