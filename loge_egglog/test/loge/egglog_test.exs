defmodule Loge.EgglogTest do
  use ExUnit.Case, async: true

  test "registers the language and its engine when the application starts" do
    assert Loge.Egglog.Language in Loge.Registry.languages()
    assert Loge.Registry.engines_for(:egglog) == [Loge.Egglog.Engines.Egglog]
    assert Loge.Registry.language_for_extension(".egg") == {:ok, Loge.Egglog.Language}
  end
end
