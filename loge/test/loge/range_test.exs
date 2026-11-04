defmodule Loge.RangeTest do
  use ExUnit.Case, async: true

  alias Loge.Range

  doctest Loge.Range

  describe "new/2" do
    test "a line alone leaves the columns to the editor" do
      assert Range.new(3) == %Range{line: 3, column: nil, end_line: nil, end_column: nil}
    end

    test "takes columns and an end" do
      assert Range.new(2, column: 4, end_line: 3, end_column: 1) ==
               %Range{line: 2, column: 4, end_line: 3, end_column: 1}
    end

    test "rejects unknown options" do
      assert_raise ArgumentError, fn -> Range.new(1, offset: 0) end
    end
  end

  describe "from_offsets/3" do
    test "ASCII" do
      assert Range.from_offsets("abc def", 4, 3) ==
               %Range{line: 1, column: 5, end_line: 1, end_column: 8}
    end

    test "an empty range at the start" do
      assert Range.from_offsets("abc", 0, 0) ==
               %Range{line: 1, column: 1, end_line: 1, end_column: 1}
    end

    test "a range across lines" do
      assert Range.from_offsets("ab\ncd\nef", 1, 6) ==
               %Range{line: 1, column: 2, end_line: 3, end_column: 2}
    end

    test "a two-byte character is one UTF-16 code unit" do
      assert Range.from_offsets("é x", 3, 1) ==
               %Range{line: 1, column: 3, end_line: 1, end_column: 4}
    end

    test "a character outside the BMP is two UTF-16 code units" do
      assert Range.from_offsets("😀 x", 5, 1) ==
               %Range{line: 1, column: 4, end_line: 1, end_column: 5}
    end

    test "CRLF ends a line" do
      assert Range.from_offsets("a\r\nb", 3, 1) ==
               %Range{line: 2, column: 1, end_line: 2, end_column: 2}
    end

    test "an offset at the end of the source" do
      assert Range.from_offsets("ab\n", 3, 0) ==
               %Range{line: 2, column: 1, end_line: 2, end_column: 1}
    end

    test "rejects offsets past the source" do
      assert_raise FunctionClauseError, fn -> Range.from_offsets("ab", 1, 2) end
    end
  end
end
