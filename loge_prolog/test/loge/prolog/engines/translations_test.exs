defmodule Loge.Prolog.Engines.TranslationsTest do
  use ExUnit.Case, async: true

  alias Loge.{Diagnostic, Outcome, Range, Source}
  alias Loge.Prolog.Engines.{Asp, Egglog, Tptp}
  alias Loge.Prolog.Program

  doctest Asp
  doctest Egglog
  doctest Tptp

  defp text(engine, program, options \\ []) do
    assert {:ok,
            %Outcome{status: :equivalent, problem: :translation, output: %Source{text: text}}} =
             engine.run(program, options)

    text
  end

  defp outside(engine, program, options \\ []) do
    assert {:ok,
            %Outcome{status: :inappropriate, output: nil, views: [{:diagnostics, diagnostics}]}} =
             engine.run(program, options)

    diagnostics
  end

  test "each engine translates Prolog equivalently, without settings, and is registered" do
    for {engine, id, to} <- [
          {Tptp, :prolog_tptp, :tptp},
          {Asp, :prolog_asp, :asp},
          {Egglog, :prolog_egglog, :egglog}
        ] do
      assert engine.id() == id
      assert engine.languages() == [:prolog]
      assert engine.task() == {:translate, to, :equivalent}
      assert engine.roles() == []
      assert engine.controls() == []
      assert engine.config_schema() == []
      assert engine.configure([]) == :ok
      assert engine.verify([]) == :ok

      assert %{engine: engine, from: :prolog, to: to, preserves: :equivalent} in Loge.Registry.translations()
    end
  end

  describe "Program" do
    test "reads facts, rules and queries, leaving out true and declarations" do
      assert {:ok,
              [
                {1, {:clause, {"parent", [{:function, "tom", []}, {:function, "b c", []}]}, []}},
                {2,
                 {:clause, {"anc", [variable: "X", variable: "Y"]},
                  [
                    {"parent", [variable: "X", variable: "Z"]},
                    {"anc", [variable: "Z", variable: "Y"]}
                  ]}},
                {4, {:query, [{"anc", [{:function, "f", [variable: "V1"]}, {:variable, "V2"}]}]}}
              ]} =
               Program.read(
                 "parent(tom, 'b c').\nanc(X, Y) :- parent(X, Z), true, anc(Z, Y).\n:- dynamic anc/2.\n?- anc(f(_), _Who).\n",
                 []
               )
    end

    test "a variable named as a renamed one keeps its name" do
      assert {:ok, [{1, {:clause, {"p", [variable: "V1", variable: "V2"]}, []}}]} =
               Program.read("p(V1, _).", [])
    end

    test "what is no definite clause over user predicates and plain terms is outside" do
      for {term, sentence} <- [
            {"p :- X = a.", "=/2 is a control construct or a built-in"},
            {"p :- \\+ q.", "\\+/1"},
            {"p :- q ; r.", ";/2"},
            {"p :- q, !.", "!/0"},
            {"p(X) :- call(X).", "call/1"},
            {"p :- G.", "a variable"},
            {"?- write(a).", "write/1"},
            {"p(1).", "number"},
            {"p(\"s\").", "number, a string or a list"},
            {"p([a]).", "list"},
            {"s --> np.", "grammar rule"},
            {":- initialization(main).", "directive"},
            {":- [library(lists)].", "does not hold"},
            {":- include(nowhere).", "does not hold"}
          ] do
        assert {:ok, [{1, {:outside, message}}]} = Program.read(term, [])
        assert message =~ sentence
      end
    end

    test "an operator declared in the program is read" do
      assert {:ok, [{2, {:clause, {"===>", [{:function, "a", []}, {:function, "b", []}]}, []}}]} =
               Program.read(":- op(700, xfx, ===>).\na ===> b.\n", [])
    end

    test "an included source's statements stand on the directive's line" do
      family = Loge.source(:prolog, "parent(tom, bob).\nparent(bob, ann).\n")

      rules =
        Loge.source(:prolog, ":- [family].\ngrand(X, Z) :- parent(X, Y), parent(Y, Z).\n",
          includes: %{"family" => family}
        )

      assert {:ok,
              [
                {2, {:clause, {"parent", _}, []}},
                {2, {:clause, {"parent", _}, []}},
                {2, {:clause, {"grand", _}, [_, _]}},
                {3, {:query, [{"grand", _}]}}
              ]} =
               Program.read("% ask\n:- include(rules).\n?- grand(tom, Who).\n",
                 includes: %{"rules" => rules}
               )
    end

    test "sources that include each other end, and a syntax error in one is outside" do
      a = Loge.source(:prolog, ":- [b].\np.\n")
      b = Loge.source(:prolog, ":- [a].\nq.\n")

      assert {:ok, [{1, {:clause, {"q", []}, []}}, {1, {:clause, {"p", []}, []}}]} =
               Program.read(":- [a].\n", includes: %{"a" => a, "b" => b})

      assert {:ok, [{1, {:outside, message}}]} =
               Program.read(":- [bad].\n", includes: %{"bad" => Loge.source(:prolog, "p(")})

      assert message =~ "bad has a syntax error"
    end

    test "a syntax error is an error with its diagnostics" do
      assert {:error, {:invalid_program, [%Diagnostic{severity: :error}]} = reason} =
               Program.read("p(", [])

      assert Program.format_error(reason) =~ "Invalid Prolog program:\nline 1"
    end
  end

  describe "Tptp" do
    test "rules, facts and queries are clauses numbered by position" do
      assert text(Tptp, """
             parent(tom, 'Bob Jr').
             anc(X, Y) :- parent(X, Y).
             anc(X, Y) :- parent(X, Z), anc(Z, f(Y, _)).
             ?- anc(tom, Who), 'is it'(Who).
             ?- true.
             """) == """
             cnf(c1, axiom, parent(tom, 'Bob Jr')).
             cnf(c2, axiom, anc(X, Y) | ~parent(X, Y)).
             cnf(c3, axiom, anc(X, Y) | ~parent(X, Z) | ~anc(Z, f(Y, V1))).
             cnf(c4, negated_conjecture, ~anc(tom, Who) | ~'is it'(Who)).
             cnf(c5, negated_conjecture, $false).
             """
    end

    test "what is outside is positioned on its line" do
      assert [%Diagnostic{code: "fragment", severity: :error, range: %Range{line: 2}}] =
               outside(Tptp, "p.\nq :- \\+ p.\n")
    end

    test "a syntax error is the run's error" do
      assert {:error, {:invalid_program, _diagnostics} = reason} = Tptp.run("p(", [])
      assert Tptp.format_error(reason) =~ "Invalid Prolog program"
    end
  end

  describe "Asp" do
    test "Datalog is written as it is and a query as a constraint" do
      assert text(Asp, """
             edge(a, b). edge(b, c).
             path(X, Y) :- edge(X, Y).
             path(X, Y) :- edge(X, Z), path(Z, Y).
             ok.
             ?- path(a, _), ok.
             ?- true.
             """) == """
             edge(a, b).
             edge(b, c).
             path(X, Y) :- edge(X, Y).
             path(X, Y) :- edge(X, Z), path(Z, Y).
             ok.
             :- path(a, V1), ok.
             :- #true.
             """
    end

    test "function symbols, quoted atoms and unsafe rules are outside" do
      for {program, sentence} <- [
            {"p(f(a)).", "f is a function symbol with arguments"},
            {"p('A').", "A is no identifier of ASP"},
            {"'P'(a).", "P is no identifier of ASP"},
            {"p(not).", "not is no identifier of ASP"},
            {"p(X, Y) :- q(X).", "Y in the head is in no body goal"},
            {"p(X).", "X in the head is in no body goal"},
            {"p :- X = a.", "built-in"}
          ] do
        assert [%Diagnostic{message: message}] = outside(Asp, program)
        assert message =~ sentence
      end
    end

    test "includes are inlined" do
      assert text(Asp, ":- [facts].\n?- p(a).\n",
               includes: %{"facts" => Loge.source(:prolog, "p(a).")}
             ) ==
               "p(a).\n:- p(a).\n"
    end
  end

  describe "Egglog" do
    test "relations, facts, rules, then each query printed and checked" do
      assert text(Egglog, """
             edge(a, 'B c'). edge('B c', 'd"').
             path(X, Y) :- edge(X, Y).
             path(X, Y) :- path(X, Z), edge(Z, Y).
             ok.
             ?- path(a, _), ok.
             ?- ok.
             ?- true.
             """) == """
             (relation edge (String String))
             (relation path (String String))
             (relation ok ())
             (relation query1 (String))
             (relation query2 ())
             (relation query3 ())
             (edge "a" "B c")
             (edge "B c" "d\\"")
             (rule ((edge X Y)) ((path X Y)))
             (rule ((path X Z) (edge Z Y)) ((path X Y)))
             (ok)
             (rule ((path "a" V1) (ok)) ((query1 V1)))
             (rule ((ok)) ((query2)))
             (query3)
             (run-schedule (saturate (run)))
             (print-function query1)
             (print-function query2)
             (print-function query3)
             (check (query1 V1))
             (check (query2))
             (check (query3))
             """
    end

    test "a clause stated twice is one rule" do
      text = text(Egglog, "p(X) :- q(X).\np(X) :- q(X).\nq(a).\nq(a).\n")
      assert length(String.split(text, "(rule ")) == 2
      assert length(String.split(text, "(q \"a\")")) == 2
    end

    test "a query relation is named apart from the program's predicates" do
      assert text(Egglog, "query1.\n?- query1.\n") =~ "(relation query2 ())"
    end

    test "what is not Datalog, and what egglog cannot name, is outside" do
      for {program, sentence} <- [
            {"p(f(a)).", "f is a function symbol with arguments"},
            {"p(X).", "X in the head is in no body goal"},
            {"run(a).", "run cannot name a relation"},
            {"'P'(a).", "P cannot name a relation"},
            {"p(a).\np(a, b).", "p is used with 1 and 2 arguments"},
            {"p :- \\+ q.", "built-in"}
          ] do
        assert [%Diagnostic{message: message} | _] = outside(Egglog, program)
        assert message =~ sentence
      end
    end
  end
end
