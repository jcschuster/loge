defmodule Loge.Smtlib.Engines.TptpTest do
  use ExUnit.Case, async: true

  alias Loge.{Diagnostic, Outcome, Range, Source}
  alias Loge.Smtlib.Engines.Tptp

  doctest Tptp

  defp lines(script) do
    assert {:ok,
            %Outcome{
              status: :equivalent,
              problem: :translation,
              engine: :smtlib_tptp,
              output: %Source{language: :tptp, text: text}
            }} =
             Tptp.run(script, [])

    assert {:ok, _file, []} = Elixir.Tptp.from_string(text)
    String.split(text, "\n", trim: true)
  end

  defp outside(script) do
    assert {:ok,
            %Outcome{status: :inappropriate, output: nil, views: [{:diagnostics, diagnostics}]}} =
             Tptp.run(script, [])

    diagnostics
  end

  test "describes itself and is registered" do
    assert Tptp.id() == :smtlib_tptp
    assert Tptp.languages() == [:smtlib]
    assert Tptp.task() == {:translate, :tptp, :equivalent}
    assert Tptp.roles() == []
    assert Tptp.controls() == []
    assert Tptp.config_schema() == []
    assert Tptp.configure([]) == :ok
    assert Tptp.verify([]) == :ok

    assert %{engine: Tptp, from: :smtlib, to: :tptp, preserves: :equivalent} in Loge.Registry.translations()
  end

  test "sorts, functions, constants and predicates are typed symbols, in the order declared" do
    assert lines("""
           (set-logic UF)
           (declare-sort s 0)
           (declare-sort |my sort| 0)
           (declare-const c s)
           (declare-fun f (s |my sort|) s)
           (declare-fun p (s) Bool)
           (declare-fun |It's| () Bool)
           (check-sat)
           """) == [
             "tff(t1, type, s: $tType).",
             "tff(t2, type, 'my sort': $tType).",
             "tff(t3, type, c: s).",
             "tff(t4, type, f: (s * 'my sort') > s).",
             "tff(t5, type, p: s > $o).",
             "tff(t6, type, 'It\\'s': $o)."
           ]
  end

  test "the Core theory is the connectives of TPTP" do
    declarations =
      "(declare-sort s 0)(declare-const a s)(declare-const b s)(declare-const c s)(declare-const p Bool)(declare-const q Bool)(declare-const r Bool)"

    for {term, formula} <- [
          {"(not p)", "~ p"},
          {"(and p q r)", "(p & q & r)"},
          {"(or p (not q))", "(p | ~ q)"},
          {"(=> p q r)", "(p => (q => r))"},
          {"(xor p q r)", "((p <~> q) <~> r)"},
          {"(= p q r)", "((p <=> q) & (q <=> r))"},
          {"(= a b)", "(a = b)"},
          {"(= a b c)", "(a = b & b = c)"},
          {"(distinct a b c)", "(a != b & a != c & b != c)"},
          {"(distinct p q)", "((p <~> q))"},
          {"(ite p q r)", "((p => q) & (~ p => r))"},
          {"(and true false)", "($true & $false)"}
        ] do
      assert List.last(lines(declarations <> "(assert #{term})")) == "tff(a1, axiom, #{formula})."
    end
  end

  test "bound variables are named by depth, an inner one shadowing" do
    assert List.last(
             lines("""
             (declare-sort s 0)
             (declare-fun p (s s) Bool)
             (assert (forall ((x s) (y s)) (=> (exists ((x s)) (p x y)) (exists ((z s)) (p x z)))))
             """)
           ) ==
             "tff(a1, axiom, ![V1: s, V2: s]: (?[V3: s]: p(V3, V2) => ?[V3: s]: p(V1, V3)))."
  end

  test "what TF0 over uninterpreted symbols has no counterpart for is outside, positioned" do
    for {script, sentence} <- [
          {"(declare-const x Int)", "sort Int is not declared"},
          {"(declare-sort s 1)", "no counterpart"},
          {"(declare-sort s 0)(declare-fun f (Bool) s)", "no Boolean arguments"},
          {"(declare-sort s 0)(declare-const a s)(declare-const p Bool)(assert (= (ite p a a) a))",
           "of sort s, not Bool"},
          {"(declare-const p Bool)(assert (let ((q p)) q))", "no counterpart"},
          {"(declare-const p Bool)(assert (! p :named n))", "no counterpart"},
          {"(declare-const p Bool)(push 1)", "no counterpart"},
          {"(define-fun p () Bool true)", "no counterpart"},
          {"(assert q)", "q is not declared"},
          {"(declare-sort s 0)(declare-const a s)(assert a)", "of sort Bool, not s"},
          {"(declare-sort s 0)(declare-sort t 0)(declare-const a s)(declare-const b t)(assert (= a b))",
           "of sort t, not s"},
          {"(declare-sort s 0)(declare-fun p (s) Bool)(declare-const a s)(assert (p a a))",
           "not declared with 2 arguments"},
          {"(declare-sort s 0)(declare-const s s)", "is a sort already"},
          {"(declare-const s Bool)(declare-sort s 0)", "is a symbol already"}
        ] do
      assert [%Diagnostic{code: "fragment", severity: :error, message: message}] = outside(script)
      assert message =~ sentence
    end

    assert [%Diagnostic{range: %Range{line: 2}}, %Diagnostic{range: %Range{line: 3}}] =
             outside("(declare-const p Bool)\n(push 1)\n(assert (> p 1))\n")
  end

  test "an invalid script is an error" do
    assert {:error, {:invalid_script, _diagnostics} = reason} = Tptp.run("(assert", [])
    assert Tptp.format_error(reason) =~ "Invalid SMT-LIB script"
  end
end
