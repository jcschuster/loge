defmodule Loge.Asp.Engines.ClingoTest do
  use ExUnit.Case, async: true

  alias Loge.{Control, Diagnostic, Outcome}
  alias Loge.Asp.Engines.Clingo

  test "describes the engine" do
    assert Clingo.id() == :clingo
    assert Clingo.languages() == [:asp]
    assert Clingo.config_schema() == []
    assert Clingo.configure([]) == :ok
    assert Clingo.verify([]) == :ok

    assert [
             %Control{key: :models, type: :integer, default: nil},
             %Control{key: :time_limit, type: :integer, default: 10}
           ] = Clingo.controls()
  end

  test "a satisfiable program yields its first stable model" do
    assert {:ok,
            %Outcome{szs: :satisfiable, engine: :clingo, views: [{:models, [["a", "b"]]}]} =
              outcome} =
             Clingo.run("a. b :- a.", [])

    assert %{"Result" => "SATISFIABLE"} = JSON.decode!(outcome.raw)
  end

  test "models: 0 enumerates every stable model" do
    assert {:ok, %Outcome{views: [{:models, models}]}} = Clingo.run("{a; b}. :- a, b.", models: 0)
    assert Enum.sort(models) == [[], ["a"], ["b"]]
  end

  test "atoms keep their text, spaces included" do
    assert {:ok, %Outcome{views: [{:models, [[~s|p("a b")|]]}]}} = Clingo.run(~s|p("a b").|, [])
  end

  test "without a model limit, an optimisation runs to the optimum" do
    program = "{a; b}. :- not a, not b. #minimize {2,a : a; 1,b : b}. #minimize {1,c : c}."

    assert {:ok, %Outcome{szs: :satisfiable, views: [{:models, models}]} = outcome} =
             Clingo.run(program, [])

    assert List.last(models) == ["b"]
    assert %{"Result" => "OPTIMUM FOUND"} = JSON.decode!(outcome.raw)
  end

  test "clingo's warnings do not reach the output" do
    assert {:ok, %Outcome{szs: :satisfiable}} =
             Clingo.run("{a; b}. #minimize {1,a : a; 2,b : b}.", models: 1)
  end

  test "a time limit reached without a model is a timeout" do
    assert {:ok, %Outcome{szs: :timeout, views: []}} =
             Clingo.run("p(0). p(X+1) :- p(X).", time_limit: 1)
  end

  test "an unsatisfiable program has no models" do
    assert {:ok, %Outcome{szs: :unsatisfiable, views: []}} = Clingo.run("a. :- a.", [])
  end

  test "an erroneous program is an error carrying its diagnostics" do
    assert {:error, {:invalid_program, [%Diagnostic{code: "error"}]} = reason} =
             Clingo.run(Loge.source(:asp, "p(X) :- q.\nq."), [])

    assert Clingo.format_error(reason) =~ ~r/^Invalid ASP program:\nline 1: unsafe variables in: /
  end

  test "Loge.run!/3 solves through the engine" do
    assert %Outcome{szs: :satisfiable} = Loge.run!(Clingo, "a.", models: 1)
  end
end
