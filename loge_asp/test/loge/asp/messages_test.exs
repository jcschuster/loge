defmodule Loge.Asp.MessagesTest do
  use ExUnit.Case, async: true

  alias Loge.{Diagnostic, Range}
  alias Loge.Asp.Messages

  @file_name "/tmp/program.lp"

  defp parse(output, source), do: Messages.parse(output, source, @file_name)

  test "a message with a body joins the body into its text" do
    output = "/tmp/program.lp:1:6-7: info: atom does not occur in any rule head:\n  b\n\n"

    assert parse(output, "a :- b.") == [
             Diagnostic.new(
               "atom-undefined",
               :info,
               Range.new(1, column: 6, end_line: 1, end_column: 7),
               "atom does not occur in any rule head: b"
             )
           ]
  end

  test "notes become related positions of the message before them" do
    output = """
    /tmp/program.lp:2:1-11: error: unsafe variables in:
      p(X):-[#inc_base];q.
    /tmp/program.lp:2:3-4: note: 'X' is unsafe

    *** ERROR: (clingo): grounding stopped because of errors
    """

    assert [%Diagnostic{code: "error", severity: :error, related: related} = diagnostic] =
             parse(output, "q.\np(X) :- q.")

    assert diagnostic.message == "unsafe variables in: p(X):-[#inc_base];q."
    assert diagnostic.range == Range.new(2, column: 1, end_line: 2, end_column: 11)
    assert related == [{Range.new(2, column: 3, end_line: 2, end_column: 4), "'X' is unsafe"}]
  end

  test "a range spanning lines" do
    assert [%Diagnostic{range: range}] =
             parse("/tmp/program.lp:1:1-2:3: error: syntax error, unexpected <EOF>\n", "a\nbc")

    assert range == Range.new(1, column: 1, end_line: 2, end_column: 3)
  end

  test "byte columns become UTF-16 columns" do
    source = "% é😀\nq :- é😀x."
    output = "/tmp/program.lp:2:6-12: error: lexer error, unexpected é😀\n"

    assert [%Diagnostic{range: range}] = parse(output, source)
    assert range == Range.new(2, column: 6, end_line: 2, end_column: 9)
  end

  test "positions past the end of the source are placed at its end" do
    assert [%Diagnostic{range: range}] =
             parse("/tmp/program.lp:2:1-2: error: lexer error, unexpected <EOF>\n", "a. %* x")

    assert range == Range.new(1, column: 8, end_line: 1, end_column: 8)
  end

  test "invalid UTF-8 in a message is replaced" do
    output = "/tmp/program.lp:1:1-2: error: lexer error, unexpected " <> <<195>> <> "\n"

    assert [%Diagnostic{message: message}] = parse(output, "é.")
    assert String.valid?(message)
  end

  test "a message about another file is placed on the first line and names the file" do
    output = "inc.lp:3:1-2: info: operation undefined:\n  (1/0)\n"

    assert [%Diagnostic{code: "operation-undefined", range: range, message: message}] =
             parse(output, "#include \"inc.lp\".")

    assert range == Range.new(1)
    assert message == "in 'inc.lp': operation undefined: (1/0)"
  end

  test "codes follow clingo's warning classes" do
    codes =
      for head <- [
            "atom does not occur in any rule head",
            "no atoms over signature occur in program",
            "operation undefined",
            "interval undefined",
            "already included file",
            "global variable in tuple of aggregate element",
            "something new"
          ] do
        [%Diagnostic{code: code}] = parse("/tmp/program.lp:1:1-2: warning: #{head}:\n  x\n", "a.")
        code
      end

    assert codes == [
             "atom-undefined",
             "atom-undefined",
             "operation-undefined",
             "operation-undefined",
             "file-included",
             "global-variable",
             "other"
           ]
  end

  test "lines that are not messages are ignored" do
    assert parse("{\n  \"Solver\": \"clingo\"\n}\n", "a.") == []
  end
end
