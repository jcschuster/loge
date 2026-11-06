defmodule Loge.PrologTest do
  use ExUnit.Case, async: true

  test "registers the language and its engine when the application starts" do
    assert Loge.Prolog.Language in Loge.Registry.languages()
    assert Loge.Registry.engines_for(:prolog) == [Loge.Prolog.Engines.Swipl]
    assert Loge.Registry.language_for_extension(".pl") == {:ok, Loge.Prolog.Language}
  end
end
