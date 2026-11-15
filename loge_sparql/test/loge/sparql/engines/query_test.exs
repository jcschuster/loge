defmodule Loge.Sparql.Engines.QueryTest do
  use ExUnit.Case, async: true

  alias Loge.{Control, Diagnostic, Outcome, Role}
  alias Loge.Sparql.Engines.Query

  @data Loge.source(:turtle, """
        @prefix : <http://e/> .
        :alice :name "Alice" ; :knows :bob .
        :bob :name "Bob" .
        """)

  test "describes the engine" do
    assert Query.id() == :sparql_query
    assert Query.languages() == [:sparql]
    assert Query.task() == :solve
    assert Query.config_schema() == []
    assert Query.verify([]) == :ok
    assert [%Role{key: :data, languages: [:turtle], required?: true}] = Query.roles()
    assert [%Control{key: :time_limit, type: :integer, default: 30}] = Query.controls()
  end

  test "a SELECT is answered from the data graph, with rudof's CSV as the raw output" do
    query = "PREFIX : <http://e/> SELECT ?n WHERE { ?x :name ?n } ORDER BY ?n"

    assert {:ok, %Outcome{status: :yes, engine: :sparql_query, views: [table], raw: raw}} =
             Query.run(query, data: @data)

    assert table == {:table, ["n"], [[~s|"Alice"|], [~s|"Bob"|]]}
    assert raw =~ "Alice"
  end

  test "an ASK that does not hold is no" do
    assert {:ok, %Outcome{status: :no}} =
             Query.run("ASK { <http://e/bob> <http://e/knows> ?y }", data: @data)
  end

  test "a CONSTRUCT's graph is the output, and the data of the next query" do
    construct = "PREFIX : <http://e/> CONSTRUCT { ?y :knownBy ?x } WHERE { ?x :knows ?y }"

    assert {:ok, %Outcome{status: :success, output: %Loge.Source{language: :turtle}} = graph} =
             Query.run(construct, data: @data)

    assert %Outcome{status: :yes} =
             Loge.run!(Query, "ASK { <http://e/bob> <http://e/knownBy> <http://e/alice> }",
               data: graph
             )
  end

  test "a query that does not read is an error carrying its diagnostics" do
    assert {:error, {:invalid_query, [%Diagnostic{code: "syntax_error"}]} = reason} =
             Query.run("SELECT ?x WHERE {", data: @data)

    assert Query.format_error(reason) =~ ~r/^Invalid SPARQL query:\nline 1: /
  end

  test "data that does not read is an error naming it" do
    assert {:error, {:invalid_data, message} = reason} =
             Query.run("ASK {}", data: "@prefix : <http://e/> .\n:a :p .\n")

    assert message =~ "line 2"
    assert Query.format_error(reason) =~ ~r/^Invalid data graph: /
  end

  test "Loge.run!/3 needs the data role" do
    assert_raise ArgumentError, ~r/role :data/, fn -> Loge.run!(Query, "ASK {}", []) end
  end
end
