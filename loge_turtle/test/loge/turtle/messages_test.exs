defmodule Loge.Turtle.MessagesTest do
  use ExUnit.Case, async: true

  alias Loge.{Diagnostic, Range}
  alias Loge.Turtle.Messages

  @context "Data error: Failed to parse RDF data from 'string' with format 'turtle': " <>
             "Error parsing Turtle data from string: "

  test "a range on one line, its columns in characters made UTF-16" do
    source = "@prefix : <http://e/> .\n:a :p \"😀\" :c :d .\n"
    message = @context <> "Parser error at line 2 between columns 12 and 14: A dot is expected"

    assert Messages.diagnostic(message, source) ==
             Diagnostic.new(
               "syntax_error",
               :error,
               Range.new(2, column: 13, end_column: 15),
               "A dot is expected"
             )
  end

  test "a range across lines" do
    message =
      @context <>
        "Parser error between line 2 column 7 and line 3 column 1: Unexpected end of file"

    assert %Diagnostic{range: range, message: "Unexpected end of file"} =
             Messages.diagnostic(message, "a\nb\n")

    assert range == Range.new(2, column: 7, end_line: 3, end_column: 1)
  end

  test "a one-character position" do
    message = @context <> "Parser error at line 1 column 3: Unexpected character"

    assert %Diagnostic{range: range} = Messages.diagnostic(message, "abc")
    assert range == Range.new(1, column: 3, end_column: 4)
  end

  test "a message without a position is placed on the first line, whole" do
    assert Messages.diagnostic("Data error: No RDF data loaded", "") ==
             Diagnostic.new(
               "syntax_error",
               :error,
               Range.new(1),
               "Data error: No RDF data loaded"
             )
  end
end
