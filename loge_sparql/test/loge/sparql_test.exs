defmodule Loge.SparqlTest do
  use ExUnit.Case, async: true

  test "registers the language and its engines when the application starts" do
    assert Loge.Sparql.Language in Loge.Registry.languages()

    assert Loge.Registry.engines_for(:sparql) == [
             Loge.Sparql.Engines.Query,
             Loge.Sparql.Engines.Endpoint
           ]

    assert Loge.Registry.language_for_extension(".rq") == {:ok, Loge.Sparql.Language}
  end
end
