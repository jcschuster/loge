defmodule Loge.SourceTest do
  use ExUnit.Case, async: true

  alias Loge.Source

  doctest Loge.Source

  test "a source is its text in its language" do
    source = Loge.source(:fake, "p.")

    assert source == %Source{language: :fake, text: "p.", includes: %{}}
    assert Loge.Input.to_iodata(source) == "p."
    assert Loge.Input.language(source) == :fake
  end

  test "a source carries the sources it includes" do
    defs = Loge.source(:fake, "q.")

    assert Loge.source(:fake, "include(defs) p.", includes: %{"defs" => defs}).includes ==
             %{"defs" => defs}
  end

  describe "to_source/3" do
    test "binds the source to a variable" do
      assert Source.to_source(:fake, "p.", bind: "defs") == ~s|defs = Loge.source(:fake, "p.")|
    end

    test "without a variable is the source alone" do
      assert Source.to_source(:fake, "p.", []) == ~s|Loge.source(:fake, "p.")|
    end

    test "passes include variables by their names" do
      assert Source.to_source(:fake, "include(a) p.", bind: "defs", includes: ["a", "lib/x"]) ==
               ~s|defs = Loge.source(:fake, "include(a) p.", includes: %{"a" => a})|
    end

    test "rejects what is not a variable name" do
      assert_raise ArgumentError, fn -> Source.to_source(:fake, "p.", bind: "Not a var") end
    end

    test "the generated source evaluates to the binding, includes and all" do
      a = Loge.source(:fake, "q.")
      code = Source.to_source(:fake, "include(a) p.", bind: "defs", includes: ["a"])

      {source, binding} = Code.eval_string(code, a: a)

      assert binding[:defs] == source
      assert source.includes == %{"a" => a}
    end
  end

  describe "closure/2" do
    test "the given includes, then those the input carries" do
      a = Loge.source(:fake, "a.")
      b = Loge.source(:fake, "b.")
      input = Loge.source(:fake, "include(b)", includes: %{"b" => b})

      assert Source.closure(input, %{"a" => a}) == %{"a" => a, "b" => b}
    end

    test "reaches the includes of included sources" do
      base = Loge.source(:fake, "base.")
      defs = Loge.source(:fake, "include(base)", includes: %{"base" => base})

      assert Source.closure("include(defs)", %{"defs" => defs}) ==
               %{"defs" => defs, "base" => base}
    end

    test "a name keeps the source found first" do
      outer = Loge.source(:fake, "outer.")
      inner = Loge.source(:fake, "inner.")
      defs = Loge.source(:fake, "include(x)", includes: %{"x" => inner})

      assert Source.closure("p.", %{"x" => outer, "defs" => defs})["x"] == outer
    end

    test "ends on sources that include each other" do
      a = Loge.source(:fake, "include(b)", includes: %{"b" => Loge.source(:fake, "include(a)")})

      assert Map.keys(Source.closure("p.", %{"a" => a})) == ["a", "b"]
    end

    test "an outcome carries the includes of its output" do
      defs = Loge.source(:fake, "q.")
      output = Loge.source(:fake, "include(defs)", includes: %{"defs" => defs})
      outcome = %Loge.Outcome{status: :equivalent, raw: "", engine: :e, output: output}

      assert Source.closure(outcome, %{}) == %{"defs" => defs}
    end
  end
end
