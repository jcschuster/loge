defmodule Loge.Dimacs.Text do
  @moduledoc """
  The lines and tokens the formats of the DIMACS family share, read by byte offset.

  `reduce/3` folds over a source. A line whose first character other than a blank is
  `c` is a comment and skipped. One whose first such character is `p` is a problem
  line, given whole without its trailing blanks. Every other blank-separated token is
  given as it is. Blanks are spaces, tabs and carriage returns; a token ends at a blank
  or a line end. What a token means is the format's to read.
  """

  alias Loge.{Diagnostic, Range}

  @typedoc "A problem line or a token, with the byte offset it starts at."
  @type item :: {:problem | :token, binary(), non_neg_integer()}

  @blank ~c" \t\r"

  @doc "Folds `fun` over the problem lines and tokens of `source`, in source order."
  @spec reduce(binary(), acc, (item(), acc -> acc)) :: acc when acc: term()
  def reduce(source, acc, fun) when is_binary(source), do: line(source, 0, acc, {source, fun})

  @doc """
  Reads a token as an integer: `0`, or an optional `-` before digits without a leading
  zero.

      iex> Loge.Dimacs.Text.integer("-12")
      {:ok, -12}
      iex> Loge.Dimacs.Text.integer("012")
      :error
  """
  @spec integer(binary()) :: {:ok, integer()} | :error
  def integer("-" <> digits) do
    case natural(digits) do
      {:ok, n} when n > 0 -> {:ok, -n}
      _ -> :error
    end
  end

  def integer(digits), do: natural(digits)

  @doc "Reads a token as a natural number: `0`, or digits without a leading zero."
  @spec natural(binary()) :: {:ok, non_neg_integer()} | :error
  def natural("0"), do: {:ok, 0}

  def natural(<<digit, _::binary>> = digits) when digit in ?1..?9 do
    case Integer.parse(digits) do
      {n, ""} -> {:ok, n}
      _ -> :error
    end
  end

  def natural(_text), do: :error

  @doc "An `:error` diagnostic on the `length` bytes of `source` at byte `at`."
  @spec error(binary(), String.t(), non_neg_integer(), non_neg_integer(), String.t()) ::
          Diagnostic.t()
  def error(source, code, at, length, message),
    do: Diagnostic.new(code, :error, Range.from_offsets(source, at, length), message)

  @doc "Diagnostics in source order."
  @spec in_order([Diagnostic.t()]) :: [Diagnostic.t()]
  def in_order(diagnostics), do: Enum.sort_by(diagnostics, &{&1.range.line, &1.range.column || 0})

  defp line(<<char, rest::binary>>, at, acc, c) when char in @blank,
    do: line(rest, at + 1, acc, c)

  defp line(<<?c, rest::binary>>, at, acc, c), do: comment(rest, at + 1, acc, c)

  defp line(<<?p, _::binary>> = rest, at, acc, {source, fun} = c) do
    length = line_length(rest, 0)
    <<_::binary-size(^length), rest::binary>> = rest
    text = source |> binary_part(at, length) |> String.trim_trailing()
    tokens(rest, at + length, fun.({:problem, text, at}, acc), c)
  end

  defp line(rest, at, acc, c), do: tokens(rest, at, acc, c)

  defp comment(<<?\n, rest::binary>>, at, acc, c), do: line(rest, at + 1, acc, c)
  defp comment(<<_, rest::binary>>, at, acc, c), do: comment(rest, at + 1, acc, c)
  defp comment(<<>>, _at, acc, _c), do: acc

  defp tokens(<<char, rest::binary>>, at, acc, c) when char in @blank,
    do: tokens(rest, at + 1, acc, c)

  defp tokens(<<?\n, rest::binary>>, at, acc, c), do: line(rest, at + 1, acc, c)
  defp tokens(<<>>, _at, acc, _c), do: acc

  defp tokens(rest, at, acc, {source, fun} = c) do
    length = token_length(rest, 0)
    <<_::binary-size(^length), rest::binary>> = rest
    tokens(rest, at + length, fun.({:token, binary_part(source, at, length), at}, acc), c)
  end

  defp line_length(<<char, rest::binary>>, length) when char != ?\n,
    do: line_length(rest, length + 1)

  defp line_length(_rest, length), do: length

  defp token_length(<<char, rest::binary>>, length) when char not in [?\n | @blank],
    do: token_length(rest, length + 1)

  defp token_length(_rest, length), do: length
end
