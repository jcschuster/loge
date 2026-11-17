defmodule Loge.TurtleTest do
  use ExUnit.Case, async: true

  test "registers the language and its engine when the application starts" do
    assert Loge.Turtle.Language in Loge.Registry.languages()

    assert Loge.Registry.engines_for(:turtle) == [
             Loge.Turtle.Engines.Shacl,
             Loge.Turtle.Engines.Tptp,
             Loge.Turtle.Engines.Prolog,
             Loge.Turtle.Engines.Asp
           ]

    assert Loge.Registry.language_for_extension(".ttl") == {:ok, Loge.Turtle.Language}
  end
end
