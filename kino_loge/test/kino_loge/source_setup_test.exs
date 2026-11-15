defmodule KinoLoge.SourceSetupTest do
  use ExUnit.Case, async: true

  alias KinoLoge.{Fake, SourceSetup}

  test "a new cell takes the first language and binds the variable it is given" do
    setup = SourceSetup.from_attrs(%{"variable" => "source"})

    assert setup == %SourceSetup{language: Fake.Language, variable: "source", source: ""}
  end

  test "attrs round-trip, through JSON as a notebook stores them" do
    setup =
      %{"variable" => "defs"}
      |> SourceSetup.from_attrs()
      |> SourceSetup.put_language("other")
      |> SourceSetup.put_source("fact")

    stored = setup |> SourceSetup.to_attrs() |> JSON.encode!() |> JSON.decode!()
    assert SourceSetup.from_attrs(stored) == setup
  end

  test "every language is offered, an engine or not" do
    assert SourceSetup.put_language(SourceSetup.from_attrs(%{}), "other").language == Fake.Other
  end

  test "an unknown language or name in attrs falls back to the defaults" do
    assert SourceSetup.from_attrs(%{"language" => "gone", "variable" => "Not one"}) ==
             SourceSetup.from_attrs(%{})

    assert SourceSetup.from_attrs(%{}).variable == "source"
  end

  test "put_variable/2 takes a variable name only" do
    setup = SourceSetup.from_attrs(%{"variable" => "defs"})

    assert SourceSetup.put_variable(setup, "axioms").variable == "axioms"
    assert SourceSetup.put_variable(setup, "") == setup
    assert SourceSetup.put_variable(setup, "Not one") == setup
    assert SourceSetup.put_language(setup, "nope") == setup
  end

  test "to_source/1 binds the source with the includes it names" do
    source =
      %{"variable" => "problem", "source" => "include defs\nquery"}
      |> SourceSetup.from_attrs()
      |> SourceSetup.to_source()

    assert source ==
             ~s|problem = Loge.source(:fake, "include defs\\nquery", includes: %{"defs" => defs})|
  end
end
