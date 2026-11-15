defmodule Loge.Shex.MessagesTest do
  use ExUnit.Case, async: true

  alias Loge.{Diagnostic, Range}
  alias Loge.Shex.Messages

  @schema_context "Schema is malformed. Error during parsing:\nShEx error: Failed to parse ShEx " <>
                    "schema from 'string' in format 'ShExC': Parsing error: "

  test "the innermost position, with the innermost message that is not a parser's own" do
    source = ~s|<http://e/S> { <http://e/p> ["😀"] } <http://e/T> { ] }|

    message =
      @schema_context <>
        """
        Parse error on line 1, column 38: Expected ShEx statement
        at "…"
        Context:
          Parse error on line 1, column 38: Expected shape expression declaration
          Context:
            Parse error on line 1, column 51: Expected shape expression definition or external 
            Context:
              Parse error on line 1, column 51: Syntax error: Alternative
              Context:
                Parse error on line 1, column 51: Syntax error: Tag
        """

    assert %Diagnostic{code: "syntax_error", severity: :error, range: range, message: text} =
             diagnostic = Messages.diagnostic(message, source)

    assert range == Range.new(1, column: 52, end_column: 53)
    assert text == "Expected shape expression definition or external"

    assert diagnostic.related == [
             {Range.new(1, column: 39, end_column: 40), "Expected ShEx statement"}
           ]
  end

  test "a shape map's error at the position the parser stopped" do
    message =
      "ShEx error: Failed to parse ShapeMap from 'string': Parsing error: " <>
        """
        Parse error on line 1, column 1: Expected ShapeMap association
        Context:
          Parse error on line 1, column 13: Expected "@"
          Context:
            Parse error on line 1, column 14: Syntax error: Tag
        """

    assert %Diagnostic{range: range, message: ~s|Expected "@"|} =
             Messages.diagnostic(message, "<http://e/a> <http://e/S>")

    assert range == Range.new(1, column: 14, end_column: 15)
    assert Messages.syntax?(message)
  end

  test "an error without a position is placed on the first line, in rudof's words" do
    message =
      "ShEx error: Failed to parse ShapeMap from 'string': Error obtaining IRI for 'ex:a': " <>
        "Alias 'ex' not found in prefix map\nAvailable aliases: []"

    assert Messages.diagnostic(message, "ex:a@<http://e/S>") ==
             Diagnostic.new(
               "shex_error",
               :error,
               Range.new(1),
               "Error obtaining IRI for 'ex:a': Alias 'ex' not found in prefix map\nAvailable aliases: []"
             )

    refute Messages.syntax?(message)
  end

  test "a schema that compiles to an error, or has negative cycles" do
    compile =
      "Schema is malformed. Error during parsing:\nShEx error: Failed to compile ShEx schema: Shape label not found http://e/T\n\n"

    assert %Diagnostic{range: %Range{line: 1, column: nil}, message: message} =
             Messages.diagnostic(compile, "")

    assert message == "Failed to compile ShEx schema: Shape label not found http://e/T"

    cycles =
      "Schema contains negative cycles in its dependency graph:\n\nNegative cycle #1:\n  Shapes involved:\n    - :S\n"

    assert %Diagnostic{message: "Schema contains negative cycles" <> _} =
             Messages.diagnostic(cycles, "")
  end
end
