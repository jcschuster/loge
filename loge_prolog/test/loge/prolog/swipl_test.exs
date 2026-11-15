defmodule Loge.Prolog.SwiplTest do
  use ExUnit.Case, async: true

  alias Loge.Prolog.Swipl

  test "a session consults a program and solves goals against it" do
    assert {:ok, {:answers, [[{"X", "b"}], [{"X", "'C d'"}]], :exhausted}, ""} =
             Swipl.with_session(fn session ->
               :ok = Swipl.consult(session, "p(b).\np('C d').", %{}, 5_000)
               Swipl.solve(session, "p(X)", 0, 5_000)
             end)
  end

  test "answers bind the named variables in order, as the toplevel writes them" do
    assert {:ok, {:answers, [answer], :exhausted}, ""} =
             Swipl.with_session(
               &Swipl.solve(&1, "Y = f(A, _B), A = [1, \"s\"|T], _H = 1", 0, 5_000)
             )

    assert answer == [{"Y", "f([1, \"s\"|T], _B)"}, {"A", "[1, \"s\"|T]"}, {"T", "T"}]
  end

  test "stops after the requested number of answers" do
    assert {:ok, {:answers, [[{"X", "1"}], [{"X", "2"}]], :more}, ""} =
             Swipl.with_session(&Swipl.solve(&1, "between(1, inf, X)", 2, 5_000))
  end

  test "a failing goal has no answers" do
    assert {:ok, {:answers, [], :exhausted}, ""} =
             Swipl.with_session(&Swipl.solve(&1, "fail", 1, 5_000))
  end

  test "a goal exceeding the time limit keeps the answers found before" do
    assert {:ok, {:answers, [[{"X", "1"}]], :timeout}, ""} =
             Swipl.with_session(fn session ->
               :ok = Swipl.consult(session, "q(1).\nq(X) :- repeat, fail, X = 2.", %{}, 5_000)
               Swipl.solve(session, "q(X)", 0, 300)
             end)
  end

  test "an exception in the goal is an error" do
    assert {:ok, {:error, {:prolog, message}}, _output} =
             Swipl.with_session(&Swipl.solve(&1, "X is foo + 1", 1, 5_000))

    assert message =~ "foo"
  end

  test "reading a program gives its diagnostics and the goals of its queries, as written" do
    source = "p(a).\n?- p(X).\nq(Y) :- true.\n?- p(é),\n   q(_).\n"

    assert {:ok, {[singleton], ["p(X)", "p(é),\n   q(_)"]}, ""} =
             Swipl.with_session(&Swipl.read(&1, source))

    assert singleton.message == "Singleton variable Y"
  end

  test "the sources a program includes are consulted with it, under their names" do
    includes = %{
      "defs" => Loge.source(:prolog, ":- include(base).\np(defs)."),
      "base" => Loge.source(:prolog, "q(base).")
    }

    assert {:ok, {:answers, [[{"X", "defs"}, {"Y", "base"}]], :exhausted}, ""} =
             Swipl.with_session(fn session ->
               :ok = Swipl.consult(session, ":- [defs].\n", includes, 5_000)
               Swipl.solve(session, "p(X), q(Y)", 0, 5_000)
             end)
  end

  test "consulting leaves the queries out" do
    assert {:ok, {:answers, [[{"X", "a"}]], :exhausted}, ""} =
             Swipl.with_session(fn session ->
               :ok = Swipl.consult(session, "p(a).\n?- assertz(p(b)), write(ran).\n", %{}, 5_000)
               Swipl.solve(session, "p(X)", 0, 5_000)
             end)
  end

  test "what the program prints is the session's output" do
    assert {:ok, {:answers, [[]], :exhausted}, "hello é\n"} =
             Swipl.with_session(fn session ->
               :ok = Swipl.consult(session, "hi :- format(\"hello é~n\").", %{}, 5_000)
               Swipl.solve(session, "hi", 0, 5_000)
             end)
  end
end
