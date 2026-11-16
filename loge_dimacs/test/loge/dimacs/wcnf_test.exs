defmodule Loge.Dimacs.WcnfTest do
  use ExUnit.Case, async: true

  alias Loge.{Diagnostic, Range}
  alias Loge.Dimacs.Wcnf

  doctest Wcnf

  defp codes(source) do
    {:error, diagnostics} = Wcnf.parse(source)
    Enum.map(diagnostics, &{&1.code, &1.range})
  end

  test "reads the format without a problem line" do
    assert Wcnf.parse("c 2022\nh 1 2 0\n5 -1\n0\n2 -2 0\nh -3 0\n") ==
             {:ok, %Wcnf{variables: 3, hard: [[1, 2], [-3]], soft: [{5, [-1]}, {2, [-2]}]}}
  end

  test "reads the format with a problem line, where a weight of at least top is hard" do
    assert Wcnf.parse("p wcnf 2 3 10\n10 1 2 0\n12 -1 0\n3 -2 0\n") ==
             {:ok, %Wcnf{variables: 2, hard: [[1, 2], [-1]], soft: [{3, [-2]}]}}
  end

  test "an empty instance" do
    assert Wcnf.parse("c nothing\n") == {:ok, %Wcnf{variables: 0, hard: [], soft: []}}
  end

  test "a malformed or late problem line" do
    assert codes("p wcnf 2 1\n1 1 0") == [
             {"DIMACS002", Range.new(1, column: 1, end_line: 1, end_column: 11)}
           ]

    assert codes("h 1 0\np wcnf 1 1 2") |> Enum.map(&elem(&1, 0)) == ["DIMACS003"]
  end

  test "a clause without a weight, or with one out of range" do
    assert codes("-1 2 0\n0 1 0\n9223372036854775808 1 0") |> Enum.map(&elem(&1, 0)) ==
             ["DIMACS004", "DIMACS004", "DIMACS004"]
  end

  test "`h` under a problem line" do
    assert codes("p wcnf 1 1 4\nh 1 0") == [
             {"DIMACS008", Range.new(2, column: 1, end_line: 2, end_column: 2)}
           ]
  end

  test "a variable beyond the problem line, a clause count other than it, an open clause" do
    assert "p wcnf 1 3 4\n4 2 0\n1 1" |> codes() |> Enum.map(&elem(&1, 0)) ==
             ["DIMACS006", "DIMACS005", "DIMACS007"]
  end

  test "renders with a problem line whose top exceeds the soft weights" do
    wcnf = %Wcnf{variables: 2, hard: [[1, 2]], soft: [{3, [-1]}, {4, [-2]}]}
    text = wcnf |> Loge.Input.to_iodata() |> IO.iodata_to_binary()

    assert text == "p wcnf 2 3 8\n8 1 2 0\n3 -1 0\n4 -2 0\n"
    assert Wcnf.parse(text) == {:ok, wcnf}
    assert Loge.Input.language(wcnf) == :wcnf
  end

  test "from_input reads any Loge.Input and keeps an instance as it is" do
    wcnf = %Wcnf{variables: 1, hard: [], soft: [{1, [1]}]}

    assert Wcnf.from_input(wcnf) == {:ok, wcnf}
    assert Wcnf.from_input(Loge.source(:wcnf, "1 1 0")) == {:ok, wcnf}
    assert {:error, {:invalid_wcnf, [%Diagnostic{code: "DIMACS004"}]}} = Wcnf.from_input("x 0")
  end
end
