defmodule Loge.Dimacs.CnfTest do
  use ExUnit.Case, async: true

  alias Loge.{Diagnostic, Range}
  alias Loge.Dimacs.Cnf

  doctest Cnf

  defp codes(source) do
    {:error, diagnostics} = Cnf.parse(source)
    Enum.map(diagnostics, &{&1.code, &1.range})
  end

  test "reads comments, the header and clauses across lines" do
    source = "c example\np cnf 3 2\n1 -3 0\nc between\n2\n3 -1 0\n"

    assert Cnf.parse(source) == {:ok, %Cnf{variables: 3, clauses: [[1, -3], [2, 3, -1]]}}
  end

  test "accepts indentation, tabs, CRLF line ends and empty clauses" do
    assert Cnf.parse("  c x\r\n\tp  cnf 1 2 \r\n 1 0 0\r\n") ==
             {:ok, %Cnf{variables: 1, clauses: [[1], []]}}
  end

  test "an empty formula has a header and nothing else" do
    assert Cnf.parse("p cnf 0 0") == {:ok, %Cnf{variables: 0, clauses: []}}
  end

  test "clauses without a header" do
    assert codes("c none\n1 2 0\n3 0") == [
             {"DIMACS001", Range.new(2, column: 1, end_line: 2, end_column: 2)}
           ]
  end

  test "a source without a header or clauses" do
    assert codes("c nothing\n") == [{"DIMACS001", Range.new(1)}]
  end

  test "a malformed header" do
    assert codes("p cnf 3\n1 0") == [
             {"DIMACS002", Range.new(1, column: 1, end_line: 1, end_column: 8)}
           ]

    assert codes("p sat 1 1\n1 0") |> Enum.map(&elem(&1, 0)) == ["DIMACS002"]
    assert codes("p cnf -1 1\n1 0") |> Enum.map(&elem(&1, 0)) == ["DIMACS002"]
  end

  test "a second header" do
    assert codes("p cnf 1 1\np cnf 1 1\n1 0") ==
             [{"DIMACS003", Range.new(2, column: 1, end_line: 2, end_column: 10)}]
  end

  test "a token that is not a literal" do
    assert codes("p cnf 2 1\n1 x2 +2 0") == [
             {"DIMACS004", Range.new(2, column: 3, end_line: 2, end_column: 5)},
             {"DIMACS004", Range.new(2, column: 6, end_line: 2, end_column: 8)}
           ]
  end

  test "a variable beyond the header's count" do
    assert {:error, [%Diagnostic{code: "DIMACS005", severity: :error, message: message}]} =
             Cnf.parse("p cnf 2 1\n1 -3 0")

    assert message =~ "3"

    assert codes("p cnf 2 1\n1 -3 0") == [
             {"DIMACS005", Range.new(2, column: 3, end_line: 2, end_column: 5)}
           ]
  end

  test "a clause count other than the header's, reported on the header" do
    assert codes("p cnf 1 2\n1 0\n") == [
             {"DIMACS006", Range.new(1, column: 1, end_line: 1, end_column: 10)}
           ]
  end

  test "a last clause without its terminating zero, which counts as a clause" do
    assert codes("p cnf 3 2\n1 0\n2\n-3") ==
             [{"DIMACS007", Range.new(3, column: 1, end_line: 4, end_column: 3)}]
  end

  test "reports every finding in source order" do
    assert "p cnf 1 3\nq 2 0\np cnf 1 1\n1" |> codes() |> Enum.map(&elem(&1, 0)) ==
             ["DIMACS006", "DIMACS004", "DIMACS005", "DIMACS003", "DIMACS007"]
  end

  test "renders as DIMACS CNF that parses back to itself" do
    cnf = %Cnf{variables: 3, clauses: [[1, -3], [], [2]]}
    text = cnf |> Loge.Input.to_iodata() |> IO.iodata_to_binary()

    assert text == "p cnf 3 3\n1 -3 0\n0\n2 0\n"
    assert Cnf.parse(text) == {:ok, cnf}
    assert Loge.Input.language(cnf) == :dimacs
  end

  test "from_input reads any Loge.Input and keeps a formula as it is" do
    cnf = %Cnf{variables: 1, clauses: [[1]]}

    assert Cnf.from_input(cnf) == {:ok, cnf}
    assert Cnf.from_input(Loge.source(:dimacs, "p cnf 1 1\n1 0")) == {:ok, cnf}
    assert {:error, {:invalid_cnf, [%Diagnostic{code: "DIMACS001"}]}} = Cnf.from_input("1 0")
  end
end
