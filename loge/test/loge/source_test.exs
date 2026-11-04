defmodule Loge.SourceTest do
  use ExUnit.Case, async: true

  test "a source is its text in its language" do
    source = Loge.source(:fake, "p.")

    assert source == %Loge.Source{language: :fake, text: "p."}
    assert Loge.Input.to_iodata(source) == "p."
    assert Loge.Input.language(source) == :fake
  end
end
