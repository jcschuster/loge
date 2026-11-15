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
             %Control{key: :answers, type: :integer, default: 1},
             %Control{key: :time_limit, type: :integer, default: 10}
           ] = Swipl.controls()
  end

  test "a query with answers is yes, with a table of bindings under the query" do
    assert {:ok, %Outcome{status: :yes, engine: :swipl, views: [view]}} =
             Swipl.run(@family <> "?- parent(bob, X).\n", answers: 0)

    assert view == {:titled, "?- parent(bob, X).", {:table, ["X"], [["ann"], ["pat"]]}}
  end

  test "a query without variables has no table" do
    assert {:ok, %Outcome{status: :yes, views: []}} =
             Swipl.run(@family <> "?- parent(tom, bob).", [])
  end

  test "a failing query is no" do
    assert {:ok, %Outcome{status: :no, views: []}} =
             Swipl.run(@family <> "?- parent(ann, _).", [])
  end

  test "a query out of time without answers is a timeout" do
    assert {:ok, %Outcome{status: :timeout}} = Swipl.run("?- repeat, fail.", time_limit: 1)
  end

  test "several queries are asked in order; the run is a success and each has its view" do
    source = @family <> "?- parent(tom, X).\n?- parent(ann, _).\n?- parent(tom, bob).\n"

    assert {:ok, %Outcome{status: :success, views: views}} = Swipl.run(source, [])

    assert views == [
             {:titled, "?- parent(tom, X).", {:table, ["X"], [["bob"]]}},
             {:titled, "?- parent(ann, _).", {:badge, "No", :neutral}},
             {:titled, "?- parent(tom, bob).", {:badge, "Yes", :positive}}
           ]
  end

  test "without a query the program is consulted, which asks nothing, so a success" do
    assert {:ok, %Outcome{status: :success, views: []}} = Swipl.run(@family, [])
  end

  test "the raw output is what consulting and the queries printed" do
    assert {:ok, %Outcome{raw: "hi\nthere\n"}} =
             Swipl.run(":- initialization(format(\"hi~n\")).\n?- format(\"there~n\").", [])
  end

  test "the includes of the run and those the source carries are consulted with it" do
    defs = Loge.source(:prolog, "parent(tom, bob).")
    program = Loge.source(:prolog, ":- [defs].\n?- parent(tom, X).", includes: %{"defs" => defs})

    assert {:ok, %Outcome{status: :yes}} = Swipl.run(program, [])

    assert {:ok, %Outcome{status: :yes}} =
             Swipl.run(":- include(defs).\n?- parent(tom, bob).", includes: %{"defs" => defs})
  end

  test "a program with syntax errors is an error carrying its diagnostics" do
    assert {:error, {:invalid_program, [%Diagnostic{code: "syntax_error"}]} = reason} =
             Swipl.run(Loge.source(:prolog, "p( :- q.\n?- true."), [])

    assert Swipl.format_error(reason) =~ ~r/^Invalid Prolog program:\nline 1: Syntax error/
  end

  test "an exception in a query is an error" do
    assert {:error, {:prolog, message} = reason} = Swipl.run("?- atom_length(X, _).", [])
    assert message =~ "instantiat"
    assert Swipl.format_error(reason) =~ "Prolog raised"
  end

  test "Loge.run!/3 solves through the engine" do
    assert %Outcome{status: :yes} = Loge.run!(Swipl, @family <> "?- parent(tom, _).", [])
  end
end
