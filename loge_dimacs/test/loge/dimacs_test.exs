defmodule Loge.DimacsTest do
  use ExUnit.Case, async: true

  test "registers the language and its engines when the application starts" do
    assert Loge.Dimacs.Language in Loge.Registry.languages()
    assert Loge.Registry.engines_for(:dimacs) == [Loge.Dimacs.Engines.Clingo]
    assert Loge.Registry.language_for_extension(".cnf") == {:ok, Loge.Dimacs.Language}
  end
end
