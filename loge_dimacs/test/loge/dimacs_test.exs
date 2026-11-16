defmodule Loge.DimacsTest do
  use ExUnit.Case, async: true

  alias Loge.Dimacs.{Engines, Languages}

  test "registers the languages and their engines when the application starts" do
    for language <- [Languages.Cnf, Languages.Wcnf, Languages.Qdimacs],
        do: assert(language in Loge.Registry.languages())

    assert Loge.Registry.engines_for(:dimacs) == [Engines.Clasp, Engines.Cadical, Engines.Kissat]
    assert Loge.Registry.engines_for(:wcnf) == [Engines.ClaspMaxsat]
    assert Loge.Registry.engines_for(:qdimacs) == [Engines.Depqbf]
    assert Loge.Registry.language_for_extension(".wcnf") == {:ok, Languages.Wcnf}
  end
end
