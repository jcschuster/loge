defmodule Loge.SourceTest do
  use ExUnit.Case, async: true

  doctest Loge.Source

  test "a source is its text in its language" do
    source = Loge.source(:fake, "p.")

    assert source == %Loge.Source{language: :fake, text: "p."}
    assert Loge.Input.to_iodata(source) == "p."
    assert Loge.Input.language(source) == :fake
  end

  test "to_source/3 binds the source to a variable" do
    assert Loge.Source.to_source(:fake, "p.", "defs") == ~s|defs = Loge.source(:fake, "p.")|
  end

  test "to_source/3 without a variable is the source alone" do
    assert Loge.Source.to_source(:fake, "p.", "") == ~s|Loge.source(:fake, "p.")|
  end

  test "to_source/3 rejects what is not a variable name" do
    assert_raise ArgumentError, fn -> Loge.Source.to_source(:fake, "p.", "Not a var") end
  end

  test "the generated source evaluates to the binding" do
    {source, binding} = Code.eval_string(Loge.Source.to_source(:fake, "p.", "defs"))
    assert binding == [defs: source]
  end
end
