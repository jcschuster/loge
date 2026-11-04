defmodule Loge.TptpTest do
  use ExUnit.Case, async: true

  test "starting the application registers every module" do
    assert Loge.Tptp.Language in Loge.Registry.languages()
    assert Loge.Registry.language_for_extension(".p") == {:ok, Loge.Tptp.Language}
    assert length(Loge.Registry.engines_for(:tptp)) == 4
  end

  test "a generated run is valid Elixir naming the engine" do
    source =
      Loge.Engine.to_source(Loge.Tptp.Engines.SystemOnTptp, "fof(a, axiom, p).", system: "E")

    assert {{:., _, [{:__aliases__, _, [:Loge]}, :run!]}, _, _} = Code.string_to_quoted!(source)
  end
end
