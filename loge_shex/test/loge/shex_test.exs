defmodule Loge.ShexTest do
  use ExUnit.Case, async: true

  test "registers both languages and the engine when the application starts" do
    assert Loge.Shex.Languages.Shexc in Loge.Registry.languages()
    assert Loge.Shex.Languages.ShapeMap in Loge.Registry.languages()
    assert Loge.Registry.engines_for(:shex) == []
    assert Loge.Registry.engines_for(:shapemap) == [Loge.Shex.Engines.Validate]
    assert Loge.Registry.language_for_extension(".shex") == {:ok, Loge.Shex.Languages.Shexc}
    assert Loge.Registry.language_for_extension(".sm") == {:ok, Loge.Shex.Languages.ShapeMap}
  end
end
