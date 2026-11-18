defmodule Loge.Turtle.Engines.FactsTest do
  use ExUnit.Case, async: true

  alias Loge.{Diagnostic, Outcome, Source}
  alias Loge.Turtle.Engines.{Asp, Prolog, Tptp}
  alias Loge.Turtle.NTriples

  doctest Asp
  doctest NTriples
  doctest Prolog
  doctest Tptp

  @turtle """
  @prefix ex: <http://ex.org/> .
  @prefix xsd: <http://www.w3.org/2001/XMLSchema#> .
  ex:a ex:knows ex:b , [ ex:name "An\\"n" ] ;
       ex:age 42 ; ex:label "hi"@en ; ex:d "2020-01-01"^^xsd:date .
  """

  defp facts(engine, turtle) do
    assert {:ok,
            %Outcome{
              status: :equi_satisfiable,
              problem: :translation,
              output: %Source{text: text}
            }} =
             engine.run(turtle, [])

    text |> String.split("\n", trim: true) |> Enum.sort()
  end

  test "each engine translates Turtle, without settings or controls, and is registered" do
    for {engine, id, to} <- [
          {Tptp, :turtle_tptp, :tptp},
          {Prolog, :turtle_prolog, :prolog},
          {Asp, :turtle_asp, :asp}
        ] do
      assert engine.id() == id
      assert engine.languages() == [:turtle]
      assert engine.task() == {:translate, to, :equi_satisfiable}
      assert engine.roles() == []
      assert engine.controls() == []
      assert engine.config_schema() == []
      assert engine.configure([]) == :ok
      assert engine.verify([]) == :ok

      assert %{engine: engine, from: :turtle, to: to, preserves: :equi_satisfiable} in Loge.Registry.translations()
    end
  end

  test "N-Triples: escapes are resolved and what is not a triple is an error" do
    assert NTriples.read(~S|<http://e/a> <http://e/p> "t\tué\U0001F600\\" .|) ==
             {:ok,
              [
                {{:iri, "http://e/a"}, {:iri, "http://e/p"},
                 {:literal, "t\tué😀\\", "http://www.w3.org/2001/XMLSchema#string", nil}}
              ]}

    assert NTriples.read("# a comment\n\n") == {:ok, []}
    assert NTriples.read("<http://e/a> <http://e/p> .") == :error
    assert NTriples.read("<http://e/a> _:b <http://e/p> .") == :error
    assert NTriples.read("<http://e/a> <http://e/p> \"x") == :error
  end

  test "Prolog: IRIs, blank nodes and literals are quoted atoms" do
    assert [
             "triple('_:" <> _,
             "triple('http://ex.org/a', 'http://ex.org/age', literal('42', 'http://www.w3.org/2001/XMLSchema#integer')).",
             "triple('http://ex.org/a', 'http://ex.org/d', literal('2020-01-01', 'http://www.w3.org/2001/XMLSchema#date')).",
             "triple('http://ex.org/a', 'http://ex.org/knows', '_:" <> _,
             "triple('http://ex.org/a', 'http://ex.org/knows', 'http://ex.org/b').",
             "triple('http://ex.org/a', 'http://ex.org/label', literal('hi', 'http://www.w3.org/1999/02/22-rdf-syntax-ns#langString', 'en'))."
           ] = facts = facts(Prolog, @turtle)

    assert hd(facts) =~
             ~S|'http://ex.org/name', literal('An"n', 'http://www.w3.org/2001/XMLSchema#string')).|
  end

  test "ASP: every word is a string" do
    facts = facts(Asp, @turtle)
    assert length(facts) == 6
    assert ~S|triple("http://ex.org/a", "http://ex.org/knows", "http://ex.org/b").| in facts

    assert Enum.any?(
             facts,
             &(&1 =~ ~S|literal("An\"n", "http://www.w3.org/2001/XMLSchema#string")|)
           )
  end

  test "TPTP: statements are numbered, and a word beyond printable ASCII is outside" do
    facts = facts(Tptp, @turtle)
    assert length(facts) == 6

    assert Enum.any?(
             facts,
             &(&1 =~
                 ~r/\Acnf\(t\d, axiom, triple\('http:\/\/ex.org\/a', 'http:\/\/ex.org\/knows', 'http:\/\/ex.org\/b'\)\)\.\z/)
           )

    assert {:ok,
            %Outcome{
              status: :inappropriate,
              output: nil,
              views: [
                {:diagnostics, [%Diagnostic{code: "fragment", message: message}, %Diagnostic{}]}
              ]
            }} =
             Tptp.run("<http://e/a> <http://e/p> \"é\" , \"ü\" .", [])

    assert message =~ ~r/printable ASCII, which "[éü]" is not/u
  end

  test "an empty graph has no facts" do
    assert facts(Prolog, "@prefix ex: <http://ex.org/> .") == []
  end

  test "Turtle that does not read is an error with its diagnostic" do
    for engine <- [Tptp, Prolog, Asp] do
      assert {:error, {:invalid_turtle, [%Diagnostic{severity: :error}]} = reason} =
               engine.run("ex:a ex:b", [])

      assert engine.format_error(reason) =~ "Invalid Turtle:\nline 1"
    end
  end
end
