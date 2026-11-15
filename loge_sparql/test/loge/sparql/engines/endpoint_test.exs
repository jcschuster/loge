defmodule Loge.Sparql.Engines.EndpointTest do
  use ExUnit.Case, async: true

  alias Loge.{Control, Outcome}
  alias Loge.Sparql.{Engines.Endpoint, EndpointStub}

  @answer ~s|{"head":{"vars":["x"]},"results":{"bindings":[{"x":{"type":"uri","value":"http://e/a"}}]}}|

  test "describes the engine" do
    assert Endpoint.id() == :sparql_endpoint
    assert Endpoint.languages() == [:sparql]
    assert Endpoint.task() == :solve
    assert Endpoint.roles() == []

    assert [
             %Control{key: :endpoint, type: :text, choices: {:dynamic, names}},
             %Control{key: :time_limit, type: :integer, default: 30}
           ] = Endpoint.controls()

    assert "Wikidata" in names.()
  end

  test "the query is sent to the endpoint and its answer read as a local one" do
    url = EndpointStub.start(@answer)

    assert {:ok, %Outcome{status: :yes, engine: :sparql_endpoint, views: [table]}} =
             Endpoint.run("SELECT ?x WHERE { ?x ?p ?o }", endpoint: url)

    assert table == {:table, ["x"], [["<http://e/a>"]]}
    assert_received {:request, "GET /sparql?query=SELECT+%3Fx" <> _}
  end

  test "a run without an endpoint, or with one that is no name or URL, is an error" do
    assert {:error, :no_endpoint = reason} = Endpoint.run("ASK {}", [])
    assert Endpoint.format_error(reason) =~ "endpoint"

    assert {:error, {:invalid_endpoint, message}} = Endpoint.run("ASK {}", endpoint: "Nowhere")
    assert message =~ "Nowhere"
  end

  test "a query that does not read is an error carrying its diagnostics, sent nowhere" do
    url = EndpointStub.start(@answer)

    assert {:error, {:invalid_query, [_diagnostic]}} =
             Endpoint.run("SELECT ?x WHERE {", endpoint: url)

    refute_received {:request, _}
  end
end
