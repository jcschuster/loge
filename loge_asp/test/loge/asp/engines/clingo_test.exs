defmodule Loge.Asp.Engines.ClingoTest do
  use ExUnit.Case, async: true

  alias Loge.{Control, Diagnostic, Outcome}
  alias Loge.Asp.Engines.Clingo

  test "describes the engine" do
    assert Clingo.id() == :clingo
    assert Clingo.languages() == [:asp]
    assert Clingo.roles() == []
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
            %Outcome{
              status: :satisfiable,
              problem: :satisfiability,
              engine: :clingo,
              views: [{:text, "% Answer: 1\na. b.\n", "asp"}]
            } =
              outcome} =
             Clingo.run("a. b :- a.", [])

    assert %{"Result" => "SATISFIABLE"} = JSON.decode!(outcome.raw)
  end

  test "models: 0 enumerates every stable model" do
    assert {:ok, %Outcome{views: [{:text, text, "asp"}]}} =
             Clingo.run("{a; b}. :- a, b.", models: 0)

    assert length(Regex.scan(~r/^% Answer: \d$/m, text)) == 3

    assert text |> String.split("\n", trim: true) |> Enum.reject(&(&1 =~ "%")) |> Enum.sort() == [
             "a.",
             "b."
           ]
  end

  test "the includes of the run and those the source carries are grounded with it" do
    defs = Loge.source(:asp, "b.")
    program = Loge.source(:asp, "#include \"defs\".\na :- b.", includes: %{"defs" => defs})

    assert {:ok, %Outcome{views: [{:text, "% Answer: 1\nb. a.\n", "asp"}]}} =
             Clingo.run(program, [])

    assert {:ok, %Outcome{views: [{:text, "% Answer: 1\nb. a.\n", "asp"}]}} =
             Clingo.run("#include \"defs\".\na :- b.", includes: %{"defs" => defs})
  end

  test "an include no source of that name holds is an invalid program" do
    assert {:error, {:invalid_program, [%Diagnostic{severity: :error, message: message}]}} =
             Clingo.run("#include \"defs\".", [])

    assert message =~ "could not be opened"
  end

  test "atoms keep their text, spaces included, as facts" do
    assert {:ok, %Outcome{views: [{:text, ~s|% Answer: 1\np("a b").\n|, "asp"}]}} =
             Clingo.run(~s|p("a b").|, [])
  end

  test "without a model limit, an optimisation runs to the optimum and says so" do
    program = "{a; b}. :- not a, not b. #minimize {2,a : a; 1,b : b}. #minimize {1,c : c}."

    assert {:ok,
            %Outcome{
              status: :satisfiable,
              views: [{:badge, "optimum found", :positive}, {:text, text, "asp"}]
            } = outcome} = Clingo.run(program, [])

    assert String.ends_with?(text, "\nb.\n% Optimization: 1\n")
    assert %{"Result" => "OPTIMUM FOUND"} = JSON.decode!(outcome.raw)
  end

  test "clingo's warnings do not reach the output" do
    assert {:ok, %Outcome{status: :satisfiable}} =
             Clingo.run("{a; b}. #minimize {1,a : a; 2,b : b}.", models: 1)
  end

  test "an optimisation stopped by the model limit is not an optimum" do
    assert {:ok, %Outcome{status: :satisfiable, views: [{:text, _models, "asp"}]}} =
             Clingo.run("{a; b}. #minimize {1,a : a; 2,b : b}.", models: 1)
  end

  test "a time limit reached without a model is a timeout" do
    assert {:ok, %Outcome{status: :timeout, views: []}} =
             Clingo.run("p(0). p(X+1) :- p(X).", time_limit: 1)
  end

  test "an unsatisfiable program has no models" do
    assert {:ok, %Outcome{status: :unsatisfiable, views: []}} = Clingo.run("a. :- a.", [])
  end

  test "an erroneous program is an error carrying its diagnostics" do
    assert {:error, {:invalid_program, [%Diagnostic{code: "error"}]} = reason} =
             Clingo.run(Loge.source(:asp, "p(X) :- q.\nq."), [])

    assert Clingo.format_error(reason) =~ ~r/^Invalid ASP program:\nline 1: unsafe variables in: /
  end

  test "Loge.run!/3 solves through the engine" do
    assert %Outcome{status: :satisfiable} = Loge.run!(Clingo, "a.", models: 1)
  end
end
