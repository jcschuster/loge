defmodule KinoLoge.SetupTest do
  use ExUnit.Case, async: true

  alias KinoLoge.Fake
  alias KinoLoge.Setup

  test "a new cell takes the first language, its first engine and the control defaults" do
    setup = Setup.from_attrs(%{})

    assert setup.language == Fake.Language
    assert setup.engine == Fake.Engine

    assert setup.options == [
             system: "A",
             mode: :fast,
             limit: 5,
             count: nil,
             method: nil,
             verbose: false
           ]

    assert setup.input == nil
    assert setup.roles == []
    assert setup.variable == ""
    assert setup.source == ""
  end

  test "attrs round-trip, through JSON as a notebook stores them" do
    setup =
      %{}
      |> Setup.from_attrs()
      |> Setup.put_option("mode", "slow")
      |> Setup.put_option("limit", "12")
      |> Setup.put_input("problem")
      |> Setup.put_variable("result")
      |> Setup.put_source("include defs")

    stored = setup |> Setup.to_attrs() |> JSON.encode!() |> JSON.decode!()
    assert Setup.from_attrs(stored) == setup
  end

  test "unknown ids and names in attrs fall back to the defaults" do
    setup =
      Setup.from_attrs(%{
        "language" => "gone",
        "engine" => "gone",
        "options" => %{"x" => 1},
        "input" => "Not a name",
        "variable" => "Not one either"
      })

    assert setup == Setup.from_attrs(%{})
  end

  test "a language without an engine is not offered" do
    assert Setup.languages() == [Fake.Language]
    assert Setup.from_attrs(%{"language" => "other"}).language == Fake.Language

    setup = Setup.from_attrs(%{})
    assert Setup.put_language(setup, "other") == setup
  end

  test "an unknown language or engine changes nothing" do
    setup = Setup.from_attrs(%{})

    assert Setup.put_language(setup, "nope") == setup
    assert Setup.put_engine(setup, "nope") == setup
    assert Setup.put_engine(setup, nil) == setup
  end

  describe "roles" do
    setup do
      %{setup: Setup.from_attrs(%{"engine" => "validator"})}
    end

    test "an engine's roles start unset, in role order", %{setup: setup} do
      assert setup.roles == [data: nil, schema: nil]
    end

    test "put_role/3 sets a role to a variable name or unsets it", %{setup: setup} do
      setup = Setup.put_role(setup, "data", "graph")
      assert setup.roles == [data: "graph", schema: nil]
      assert Setup.put_role(setup, "data", nil).roles == [data: nil, schema: nil]
    end

    test "put_role/3 ignores a key the engine has no role for, and a name that is no variable",
         %{setup: setup} do
      assert Setup.put_role(setup, "graph", "graph") == setup
      assert Setup.put_role(setup, "data", "Not one") == setup
    end

    test "roles round-trip through the attrs", %{setup: setup} do
      setup = Setup.put_role(setup, "schema", "shapes")
      stored = setup |> Setup.to_attrs() |> JSON.encode!() |> JSON.decode!()

      assert stored["roles"] == %{"data" => nil, "schema" => "shapes"}
      assert Setup.from_attrs(stored) == setup
    end

    test "unknown keys and names in attrs leave roles unset" do
      attrs = %{"engine" => "validator", "roles" => %{"data" => "Not one", "x" => "y"}}
      assert Setup.from_attrs(attrs).roles == [data: nil, schema: nil]
      assert Setup.from_attrs(Map.put(attrs, "roles", "nope")).roles == [data: nil, schema: nil]
    end

    test "another engine has its own roles", %{setup: setup} do
      setup = setup |> Setup.put_role("data", "graph") |> Setup.put_engine("fake_engine")
      assert setup.roles == []
      assert Setup.put_engine(setup, "validator").roles == [data: nil, schema: nil]
    end

    test "the generated run passes each set role its variable", %{setup: setup} do
      source = setup |> Setup.put_role("data", "graph") |> Setup.to_source()
      assert source == ~s|Loge.run!(KinoLoge.Fake.Validator, "", data: graph)|
    end
  end

  test "an engine is chosen among the language's engines, with its defaults" do
    setup =
      Setup.from_attrs(%{}) |> Setup.put_option("limit", 9) |> Setup.put_engine("translator")

    assert setup.engine == Fake.Translator
    assert setup.options == []
  end

  test "changing the language resets the engine, its options and the input" do
    setup =
      Setup.from_attrs(%{"engine" => "translator", "input" => "problem"})
      |> Setup.put_language("fake")

    assert setup.engine == Fake.Engine
    assert setup.input == nil
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

    test "an empty integer field unsets a control without a default", %{setup: setup} do
      setup = Setup.put_option(setup, "count", "3")

      assert setup.options[:count] == 3
      assert Setup.put_option(setup, "count", "").options[:count] == nil
    end

    test "ignores a value outside the control's type or choices", %{setup: setup} do
      for {key, value} <- [
            {"limit", "7x"},
            {"limit", ""},
            {"verbose", "yes"},
            {"system", "C"},
            {"mode", "medium"},
            {"nope", 1}
          ] do
        assert Setup.put_option(setup, key, value) == setup, "#{key} = #{inspect(value)}"
      end
    end
  end

  test "put_input/2 takes the editor or a variable name" do
    setup = Setup.from_attrs(%{})

    assert Setup.put_input(setup, "problem").input == "problem"
    assert Setup.put_input(setup, "problem") |> Setup.put_input(nil) |> Map.get(:input) == nil
    assert Setup.put_input(setup, "Not one") == setup
  end

  test "put_variable/2 takes a variable name or nothing" do
    setup = Setup.from_attrs(%{})

    assert Setup.put_variable(setup, "result").variable == "result"
    assert Setup.put_variable(setup, "").variable == ""
    assert Setup.put_variable(setup, "Not one") == setup
  end

  describe "to_source/1" do
    test "runs the engine on the editor's source with the set options and its includes" do
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

    test "runs the engine on a bound input, which carries its own includes" do
      source =
        %{"engine" => "translator", "input" => "problem", "source" => "include defs"}
        |> Setup.from_attrs()
        |> Setup.to_source()

      assert source == ~s|Loge.run!(KinoLoge.Fake.Translator, problem, [])|
    end

    test "binds the outcome to the result name" do
      source =
        %{"engine" => "translator", "variable" => "cnf", "source" => "p"}
        |> Setup.from_attrs()
        |> Setup.to_source()

      assert source == ~s|cnf = Loge.run!(KinoLoge.Fake.Translator, "p", [])|
    end
  end
end
