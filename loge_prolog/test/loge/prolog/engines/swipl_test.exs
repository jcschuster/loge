defmodule Loge.Prolog.Engines.SwiplTest do
  use ExUnit.Case, async: true

  alias Loge.{Control, Diagnostic, Outcome}
  alias Loge.Prolog.Engines.Swipl

  @family "parent(tom, bob).\nparent(bob, ann).\nparent(bob, pat).\n"

  test "describes the engine" do
    assert Swipl.id() == :swipl
    assert Swipl.languages() == [:prolog]
    assert Swipl.config_schema() == []
    assert Swipl.verify([]) == :ok

    assert [
             %Control{key: :goal, type: :text},
             %Control{key: :answers, type: :integer, default: 1},
             %Control{key: :time_limit, type: :integer, default: 10}
           ] = Swipl.controls()
  end

  test "a goal with answers is true, with a table of bindings and no SZS status" do
    assert {:ok, %Outcome{szs: nil, engine: :swipl, views: [{:badge, "true", :positive}, table]}} =
             Swipl.run(@family, goal: "parent(bob, X)", answers: 0)

    assert table == {:table, ["X"], [["ann"], ["pat"]]}
  end

  test "a goal without variables has no table" do
    assert {:ok, %Outcome{szs: nil, views: [{:badge, "true", :positive}]}} =
             Swipl.run(@family, goal: "parent(tom, bob)")
  end

  test "a failing goal is false" do
    assert {:ok, %Outcome{szs: nil, views: [{:badge, "false", :neutral}]}} =
             Swipl.run(@family, goal: "parent(ann, _)")
  end

  test "a goal out of time without answers is a timeout" do
    assert {:ok, %Outcome{szs: :timeout}} = Swipl.run("", goal: "repeat, fail", time_limit: 1)
  end

  test "without a goal the program is consulted" do
    assert {:ok, %Outcome{szs: nil, views: [{:badge, "consulted", :positive}]}} =
             Swipl.run(@family, [])
  end

  test "the raw output is what the program printed" do
    assert {:ok, %Outcome{raw: "hi\n"}} = Swipl.run(":- initialization(format(\"hi~n\")).", [])
  end

  test "a program with syntax errors is an error carrying its diagnostics" do
    assert {:error, {:invalid_program, [%Diagnostic{code: "syntax_error"}]} = reason} =
             Swipl.run(Loge.source(:prolog, "p( :- q."), goal: "true")

    assert Swipl.format_error(reason) =~ ~r/^Invalid Prolog program:\nline 1: Syntax error/
  end

  test "an exception in the goal is an error" do
    assert {:error, {:prolog, message} = reason} = Swipl.run("", goal: "atom_length(X, _)")
    assert message =~ "instantiat"
    assert Swipl.format_error(reason) =~ "Prolog raised"
  end

  test "Loge.run!/3 solves through the engine" do
    assert %Outcome{views: [{:badge, "true", _tone}]} =
             Loge.run!(Swipl, @family, goal: "parent(tom, _)")
  end
end
