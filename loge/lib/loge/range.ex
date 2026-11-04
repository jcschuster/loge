defmodule Loge.Range do
  @moduledoc """
  Where a diagnostic sits in the source, in the position format of Kino's smart-cell
  editor diagnostics.

  Lines and columns are 1-based. Columns count UTF-16 code units, which equal
  characters except for characters outside the Basic Multilingual Plane, which count
  two. `end_column` is exclusive. A `nil` column lets the editor choose: `column`
  defaults to the line's first non-whitespace character, `end_line` to `line`, and
  `end_column` to the end of `end_line` without trailing whitespace.
  """

  @enforce_keys [:line]
  defstruct [:line, :column, :end_line, :end_column]

  @typedoc "A range of lines and UTF-16 columns; `nil` fields are left to the editor."
  @type t :: %__MODULE__{
          line: pos_integer(),
          column: pos_integer() | nil,
          end_line: pos_integer() | nil,
          end_column: pos_integer() | nil
        }

  @doc """
  Builds a range starting on `line`. Options are `:column`, `:end_line` and
  `:end_column`.

      iex> Loge.Range.new(2, column: 5, end_column: 9)
      %Loge.Range{line: 2, column: 5, end_line: nil, end_column: 9}
  """
  @spec new(pos_integer(), keyword()) :: t()
  def new(line, options \\ []) when is_integer(line) and line > 0 do
    options = Keyword.validate!(options, [:column, :end_line, :end_column])
    struct!(__MODULE__, [line: line] ++ options)
  end

  @doc """
  Converts `length` bytes at byte `offset` of `source` into a range.

  Scans the source once, up to the end of the range.

      iex> Loge.Range.from_offsets("ab\\ncd", 3, 2)
      %Loge.Range{line: 2, column: 1, end_line: 2, end_column: 3}
  """
  @spec from_offsets(binary(), non_neg_integer(), non_neg_integer()) :: t()
  def from_offsets(source, offset, length)
      when is_binary(source) and is_integer(offset) and is_integer(length) and offset >= 0 and
             length >= 0 and offset + length <= byte_size(source) do
    {line, column} = advance(binary_part(source, 0, offset), 1, 1)
    {end_line, end_column} = advance(binary_part(source, offset, length), line, column)
    %__MODULE__{line: line, column: column, end_line: end_line, end_column: end_column}
  end

  defp advance(<<?\n, rest::binary>>, line, _column), do: advance(rest, line + 1, 1)

  defp advance(<<char::utf8, rest::binary>>, line, column) when char > 0xFFFF,
    do: advance(rest, line, column + 2)

  defp advance(<<_char::utf8, rest::binary>>, line, column), do: advance(rest, line, column + 1)
  defp advance(<<_byte, rest::binary>>, line, column), do: advance(rest, line, column + 1)
  defp advance(<<>>, line, column), do: {line, column}
end
