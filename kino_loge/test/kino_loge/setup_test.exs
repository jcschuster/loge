defmodule KinoLoge.SetupTest do
  use ExUnit.Case, async: true

  alias KinoLoge.Fake
  alias KinoLoge.Setup

  test "a new cell takes the first language, its first engine and the control defaults" do
    setup = Setup.from_attrs(%{})

    assert setup.language == Fake.Language
    assert setup.engine == Fake.Engine
    assert setup.options == [system: "A", mode: :fast, limit: 5, method: nil, verbose: false]
    assert setup.source == ""
  end

  test "attrs round-trip, through JSON as a notebook stores them" do
    setup =
      %{}
      |> Setup.from_attrs()
      |> Setup.put_option("mode", "slow")
      |> Setup.put_option("limit", "12")
      |> Setup.put_source("include defs")

    stored = setup |> Setup.to_attrs() |> JSON.encode!() |> JSON.decode!()
    assert Setup.from_attrs(stored) == setup
  end

  test "unknown ids in attrs fall back to the defaults" do
    setup =
      Setup.from_attrs(%{"language" => "gone", "engine" => "gone", "options" => %{"x" => 1}})

    assert setup.language == Fake.Language
    assert setup.engine == Fake.Engine
  end

  test "a nil engine is a definitions cell" do
    assert %Setup{engine: nil, options: []} = Setup.from_attrs(%{"engine" => nil})
  end

  test "changing the language resets the engine and its options" do
    setup = Setup.from_attrs(%{}) |> Setup.put_option("limit", 9) |> Setup.put_language("other")

    assert setup.language == Fake.Other
    assert setup.engine == nil
    assert setup.options == []
  end

  test "an unknown language or engine changes nothing" do
    setup = Setup.from_attrs(%{})

    assert Setup.put_language(setup, "nope") == setup
    assert Setup.put_engine(setup, "nope") == setup
  end

  test "an engine is chosen among the language's engines" do
    setup = Setup.from_attrs(%{}) |> Setup.put_engine("second_engine")

    assert setup.engine == Fake.SecondEngine
    assert setup.options == []
    assert Setup.put_engine(setup, nil).engine == nil
  end

  describe "put_option/3" do
    setup do
      %{setup: Setup.from_attrs(%{})}
    end

    test "takes a value of the control's type", %{setup: setup} do
      assert Setup.put_option(setup, "limit", 7).options[:limit] == 7
      assert Setup.put_option(setup, "limit", "7").options[:limit] == 7
      assert Setup.put_option(setup, "verbose", true).options[:verbose] == true
      assert Setup.put_option(setup, "method", "by simp").options[:method] == "by simp"
      assert Setup.put_option(setup, "system", "B").options[:system] == "B"
      assert Setup.put_option(setup, "mode", "slow").options[:mode] == :slow
    end

    test "ignores a value outside the control's type or choices", %{setup: setup} do
      for {key, value} <- [
            {"limit", "7x"},
            {"verbose", "yes"},
            {"system", "C"},
            {"mode", "medium"},
            {"nope", 1}
          ] do
        assert Setup.put_option(setup, key, value) == setup, "#{key} = #{inspect(value)}"
      end
    end
  end

  test "put_variable/2 takes a variable name or nothing" do
    setup = Setup.from_attrs(%{})

    assert Setup.put_variable(setup, "defs").variable == "defs"
    assert Setup.put_variable(setup, "").variable == ""
    assert Setup.put_variable(setup, "Not one") == setup
  end

  describe "to_source/1" do
    test "an engine cell runs the engine with the set options and its includes" do
      source =
        %{}
        |> Setup.from_attrs()
        |> Setup.put_source("include defs\nquery")
        |> Setup.to_source()

      assert source ==
               """
               Loge.run!(KinoLoge.Fake.Engine, "include defs\\nquery",
                 system: "A",
                 mode: :fast,
                 limit: 5,
                 verbose: false,
                 includes: %{"defs" => defs}
               )\
               """
    end

    test "a definitions cell binds its source" do
      source =
        %{"engine" => nil, "variable" => "defs", "source" => "fact"}
        |> Setup.from_attrs()
        |> Setup.to_source()

      assert source == ~s|defs = Loge.source(:fake, "fact")|
    end
  end
end
