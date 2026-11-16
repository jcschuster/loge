defmodule Loge.Dimacs.QdimacsTest do
  use ExUnit.Case, async: true

  alias Loge.{Diagnostic, Range}
  alias Loge.Dimacs.Qdimacs

  doctest Qdimacs

  defp codes(source) do
    {:error, diagnostics} = Qdimacs.parse(source)
    Enum.map(diagnostics, &{&1.code, &1.range})
  end

  test "reads the prefix from the outermost set in, then the clauses" do
    source = "c q\np cnf 3 2\ne 1 0\na 2 0\ne 3 0\n1 2 3 0\n-2 -3 0\n"

    assert Qdimacs.parse(source) ==
             {:ok,
              %Qdimacs{
                variables: 3,
                prefix: [exists: [1], forall: [2], exists: [3]],
                clauses: [[1, 2, 3], [-2, -3]]
              }}
  end

  test "a DIMACS CNF file is a QDIMACS file without a prefix" do
    assert Qdimacs.parse("p cnf 2 1\n1 -2 0") ==
             {:ok, %Qdimacs{variables: 2, prefix: [], clauses: [[1, -2]]}}
  end

  test "a quantifier set after a clause" do
    assert codes("p cnf 2 2\ne 1 0\n1 2 0\na 2 0\n-1 0") == [
             {"DIMACS010", Range.new(4, column: 1, end_line: 4, end_column: 2)}
           ]
  end

  test "contiguous sets of one quantifier" do
    assert codes("p cnf 2 1\ne 1 0\ne 2 0\n1 2 0") == [
             {"DIMACS011", Range.new(3, column: 1, end_line: 3, end_column: 2)}
           ]
  end

  test "a variable bound twice, beyond the header, or negated" do
    assert "p cnf 2 1\na 1 0\ne 1 3 -2 0\n1 2 0" |> codes() |> Enum.map(&elem(&1, 0)) ==
             ["DIMACS012", "DIMACS005", "DIMACS004"]
  end

  test "an innermost universal set" do
    assert codes("p cnf 2 1\ne 1 0\na 2 0\n1 2 0") == [
             {"DIMACS013", Range.new(3, column: 1, end_line: 3, end_column: 2)}
           ]
  end

  test "a bound variable in no clause" do
    assert codes("p cnf 2 1\ne 1 2 0\n1 0") == [
             {"DIMACS014", Range.new(2, column: 5, end_line: 2, end_column: 6)}
           ]
  end

  test "an empty or unterminated quantifier set" do
    assert codes("p cnf 1 1\na 0\ne 1 0\n1 0") |> Enum.map(&elem(&1, 0)) == ["DIMACS015"]
    assert codes("p cnf 1 0\ne 1") |> Enum.map(&elem(&1, 0)) == ["DIMACS007", "DIMACS014"]
  end

  test "renders as QDIMACS that parses back to itself" do
    qbf = %Qdimacs{variables: 2, prefix: [forall: [1], exists: [2]], clauses: [[-1, 2], [1, -2]]}
    text = qbf |> Loge.Input.to_iodata() |> IO.iodata_to_binary()

    assert text == "p cnf 2 2\na 1 0\ne 2 0\n-1 2 0\n1 -2 0\n"
    assert Qdimacs.parse(text) == {:ok, qbf}
    assert Loge.Input.language(qbf) == :qdimacs
  end

  test "from_input reads any Loge.Input and keeps a formula as it is" do
    qbf = %Qdimacs{variables: 1, prefix: [exists: [1]], clauses: [[1]]}

    assert Qdimacs.from_input(qbf) == {:ok, qbf}
    assert Qdimacs.from_input(Loge.source(:qdimacs, "p cnf 1 1\ne 1 0\n1 0")) == {:ok, qbf}

    assert {:error, {:invalid_qdimacs, [%Diagnostic{code: "DIMACS001"}]}} =
             Qdimacs.from_input("1 0")
  end
end
