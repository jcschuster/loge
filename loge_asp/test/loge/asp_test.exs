defmodule Loge.AspTest do
  use ExUnit.Case, async: true

  test "registers the language and its engines when the application starts" do
    assert Loge.Asp.Language in Loge.Registry.languages()
    assert Loge.Registry.engines_for(:asp) == [Loge.Asp.Engines.Clingo, Loge.Asp.Engines.Dimacs]
    assert Loge.Registry.language_for_extension(".lp") == {:ok, Loge.Asp.Language}
  end
end
