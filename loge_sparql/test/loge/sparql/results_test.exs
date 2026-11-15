defmodule Loge.Sparql.ResultsTest do
  use ExUnit.Case, async: true

  alias Loge.Outcome
  alias Loge.Sparql.Results

  test "a SELECT with rows is yes, with a table of them" do
    result = %{kind: :select, variables: ["x", "n"], rows: [["<http://e/a>", nil]]}

    assert %Outcome{status: :yes, engine: :e, raw: "csv", views: [table], output: nil} =
             Results.outcome(:e, result, "csv")

    assert table == {:table, ["x", "n"], [["<http://e/a>", nil]]}
  end

  test "a SELECT without rows is no, without a table" do
    assert %Outcome{status: :no, views: []} =
             Results.outcome(:e, %{kind: :select, variables: [], rows: []}, "No results")
  end

  test "an ASK is yes or no" do
    assert %Outcome{status: :yes, views: []} =
             Results.outcome(:e, %{kind: :ask, boolean: true}, "")

    assert %Outcome{status: :no} = Results.outcome(:e, %{kind: :ask, boolean: false}, "")
  end

  test "a CONSTRUCT or DESCRIBE asks nothing: a success whose output is the graph, in Turtle" do
    graph = "<http://e/a> <http://e/p> 1 .\n"

    assert %Outcome{status: :success, views: [], output: output} =
             Results.outcome(:e, %{kind: :graph, graph: graph}, graph)

    assert output == Loge.source(:turtle, graph)
  end
end
