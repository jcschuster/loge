defmodule Loge.Verification.Generators do
  @moduledoc """
  Small random inputs for the verification properties: small enough for every solver
  to decide, varied enough to reach the cases a translation distinguishes.
  """

  import StreamData

  @constants ["a", "b", "c"]

  @doc "A DIMACS CNF formula over up to four variables."
  @spec cnf() :: StreamData.t(Loge.Dimacs.Cnf.t())
  def cnf do
    bind(integer(1..4), fn variables ->
      map(list_of(clause(variables), max_length: 7), fn clauses ->
        %Loge.Dimacs.Cnf{variables: variables, clauses: clauses}
      end)
    end)
  end

  @doc "A WCNF instance over up to three variables."
  @spec wcnf() :: StreamData.t(Loge.Dimacs.Wcnf.t())
  def wcnf do
    bind(integer(1..3), fn variables ->
      map(
        {list_of(clause(variables), max_length: 3),
         list_of(tuple({integer(1..9), clause(variables)}), max_length: 4)},
        fn {hard, soft} -> %Loge.Dimacs.Wcnf{variables: variables, hard: hard, soft: soft} end
      )
    end)
  end

  @doc "A QDIMACS formula over three variables, each bound, with an existential set innermost."
  @spec qbf() :: StreamData.t(Loge.Dimacs.Qdimacs.t())
  def qbf do
    map(
      {member_of([
         [forall: [1], exists: [2, 3]],
         [exists: [1], forall: [2], exists: [3]],
         [forall: [1, 2], exists: [3]],
         [exists: [1, 2, 3]]
       ]), list_of(clause(3), min_length: 1, max_length: 5)},
      fn {prefix, clauses} ->
        used = clauses |> List.flatten() |> Enum.map(&abs/1)

        %Loge.Dimacs.Qdimacs{
          variables: 3,
          prefix: prefix,
          clauses: clauses ++ Enum.map([1, 2, 3] -- used, &[&1, -&1])
        }
      end
    )
  end

  defp clause(variables) do
    literal =
      map({integer(1..variables), boolean()}, fn {n, sign} -> if sign, do: n, else: -n end)

    map(list_of(literal, max_length: 3), &Enum.uniq/1)
  end

  @doc """
  A Datalog program in Prolog syntax with one query. With `recursive: false` a
  predicate is defined from those before it only, so Prolog's search ends; with
  `recursive: true` a rule may be left-recursive. Every predicate is declared dynamic:
  Prolog raises an error for a goal of a predicate without clauses, where the clauses
  say that it fails.
  """
  @spec datalog(keyword()) :: StreamData.t(String.t())
  def datalog(options) do
    recursive = Keyword.fetch!(options, :recursive)

    map(
      {list_of(fact(), min_length: 1, max_length: 6), list_of(rule(1, recursive), max_length: 2),
       list_of(rule(2, recursive), max_length: 2), query()},
      fn {facts, first, second, query} ->
        Enum.join(
          [":- dynamic e/2, f/2, p1/2, p2/2." | Enum.uniq(facts)] ++ first ++ second ++ [query],
          "\n"
        ) <> "\n"
      end
    )
  end

  defp fact do
    map({member_of(["e", "f"]), member_of(@constants), member_of(@constants)}, fn {p, s, o} ->
      "#{p}(#{s}, #{o})."
    end)
  end

  defp rule(level, recursive) do
    lower = ["e", "f"] ++ Enum.map(1..(level - 1)//1, &"p#{&1}")
    first = if recursive, do: lower ++ ["p#{level}"], else: lower

    map(
      {member_of(first), member_of(["Z", "Y", "a"]), member_of(lower), member_of(["Z", "X", "b"]),
       boolean()},
      fn
        {g1, t1, g2, t2, true} -> "p#{level}(X, Y) :- #{g1}(X, #{t1}), #{g2}(#{t2}, Y)."
        {g1, _t1, _g2, _t2, false} -> "p#{level}(X, Y) :- #{g1}(X, Y)."
      end
    )
  end

  defp query do
    map(
      {member_of(["e", "p1", "p2"]), member_of(@constants), member_of(@constants ++ ["W"])},
      fn {p, s, o} -> "?- #{p}(#{s}, #{o})." end
    )
  end

  @doc "A TPTP problem of clauses without function symbols or equality."
  @spec clauses() :: StreamData.t(String.t())
  def clauses do
    literal =
      map(
        {member_of(["", "~ "]), member_of(["p", "q"]), member_of(["X", "Y", "a", "b"]),
         member_of(["X", "a"])},
        fn
          {sign, "p", s, _t} -> "#{sign}p(#{s})"
          {sign, "q", s, t} -> "#{sign}q(#{s}, #{t})"
        end
      )

    map(
      list_of(list_of(literal, min_length: 1, max_length: 3), min_length: 1, max_length: 5),
      fn clauses ->
        clauses
        |> Enum.with_index()
        |> Enum.map_join("\n", fn {clause, n} ->
          "cnf(c#{n}, axiom, #{Enum.join(clause, " | ")})."
        end)
      end
    )
  end

  @doc "A first-order problem: axioms and a conjecture over a unary and a binary predicate, a function and a constant."
  @spec first_order() :: StreamData.t(String.t())
  def first_order do
    map({list_of(formula(), min_length: 1, max_length: 3), formula()}, fn {axioms, conjecture} ->
      axioms
      |> Enum.with_index()
      |> Enum.map_join("\n", fn {axiom, n} -> "fof(a#{n}, axiom, #{axiom})." end)
      |> Kernel.<>("\nfof(c, conjecture, #{conjecture}).\n")
    end)
  end

  defp formula do
    atom =
      one_of([
        map(individual(), &"p(#{&1})"),
        map({individual(), individual()}, fn {s, t} -> "q(#{s}, #{t})" end),
        map({individual(), individual()}, fn {s, t} -> "#{s} = #{t}" end)
      ])

    body =
      tree(atom, fn inner ->
        one_of([
          map(inner, &"~ (#{&1})"),
          map({inner, member_of(["&", "|", "=>", "<=>"]), inner}, fn {l, c, r} ->
            "((#{l}) #{c} (#{r}))"
          end)
        ])
      end)

    map({member_of(["!", "?"]), member_of(["!", "?"]), body}, fn {q1, q2, body} ->
      "#{q1}[X]: #{q2}[Y]: (#{body})"
    end)
  end

  defp individual, do: member_of(["X", "Y", "a", "f(X)"])

  @doc "A TF0 problem over two types, with a conjecture."
  @spec typed() :: StreamData.t(String.t())
  def typed do
    atom =
      one_of([
        map(member_of(["X", "c", "g(X)"]), &"p(#{&1})"),
        map({member_of(["X", "c"]), member_of(["Y", "d"])}, fn {s, t} -> "r(#{s}, #{t})" end),
        map({member_of(["X", "c", "g(X)"]), member_of(["X", "c"])}, fn {s, t} -> "#{s} = #{t}" end),
        map(member_of(["Y", "d"]), &"#{&1} = d")
      ])

    body =
      tree(atom, fn inner ->
        one_of([
          map(inner, &"~ (#{&1})"),
          map({inner, member_of(["&", "|", "=>"]), inner}, fn {l, c, r} ->
            "((#{l}) #{c} (#{r}))"
          end)
        ])
      end)

    statement =
      map({member_of(["!", "?"]), member_of(["!", "?"]), body}, fn {q1, q2, body} ->
        "#{q1}[X: s]: #{q2}[Y: t]: (#{body})"
      end)

    map({list_of(statement, min_length: 1, max_length: 3), statement}, fn {axioms, conjecture} ->
      """
      tff(s_type, type, s: $tType).
      tff(t_type, type, t: $tType).
      tff(c_type, type, c: s).
      tff(d_type, type, d: t).
      tff(g_type, type, g: s > s).
      tff(p_type, type, p: s > $o).
      tff(r_type, type, r: (s * t) > $o).
      #{axioms |> Enum.with_index() |> Enum.map_join("\n", fn {axiom, n} -> "tff(a#{n}, axiom, #{axiom})." end)}
      tff(goal, conjecture, #{conjecture}).
      """
    end)
  end

  @doc "A tight answer set program over four atoms."
  @spec tight() :: StreamData.t(String.t())
  def tight do
    atoms = ["a", "b", "c", "d"]

    rule =
      bind(member_of(Enum.with_index(atoms)), fn {head, index} ->
        map(
          {list_of(member_of(Enum.drop(atoms, index + 1) ++ [nil]), max_length: 2),
           list_of(member_of(atoms), max_length: 2), member_of([:rule, :choice, :constraint])},
          fn {positive, negative, kind} ->
            body =
              Enum.join(
                Enum.reject(positive, &is_nil/1) ++ Enum.map(negative, &("not " <> &1)),
                ", "
              )

            case {kind, body} do
              {:rule, ""} -> "#{head}."
              {:rule, body} -> "#{head} :- #{body}."
              {:constraint, body} when body != "" -> ":- #{body}."
              {_choice, ""} -> "{ #{head} }."
              {_choice, body} -> "{ #{head} } :- #{body}."
            end
          end
        )
      end)

    map(list_of(rule, min_length: 1, max_length: 6), &Enum.join(&1, "\n"))
  end

  @doc "An SMT-LIB script over one uninterpreted sort, with a `check-sat`."
  @spec script() :: StreamData.t(String.t())
  def script do
    term = member_of(["a", "b", "(f a)", "(f b)"])

    atom =
      one_of([
        member_of(["u", "v"]),
        map(term, &"(p #{&1})"),
        map({term, term}, fn {s, t} -> "(= #{s} #{t})" end),
        constant("(forall ((x S)) (p (f x)))"),
        constant("(exists ((x S)) (not (p x)))")
      ])

    formula =
      tree(atom, fn inner ->
        one_of([
          map(inner, &"(not #{&1})"),
          map({member_of(["and", "or", "=>", "xor", "="]), inner, inner}, fn {c, l, r} ->
            "(#{c} #{l} #{r})"
          end),
          map({inner, inner, inner}, fn {c, t, e} -> "(ite #{c} #{t} #{e})" end)
        ])
      end)

    map(list_of(formula, min_length: 1, max_length: 4), fn assertions ->
      """
      (set-logic UF)
      (declare-sort S 0)
      (declare-const a S)
      (declare-const b S)
      (declare-fun f (S) S)
      (declare-fun p (S) Bool)
      (declare-const u Bool)
      (declare-const v Bool)
      #{Enum.map_join(assertions, "\n", &"(assert #{&1})")}
      (check-sat)
      """
    end)
  end

  @doc "A propositional SMT-LIB script with bit-vectors of width two."
  @spec bit_vectors() :: StreamData.t(String.t())
  def bit_vectors do
    vector = member_of(["x", "y", "#b01", "#b10", "(bvadd x y)", "(bvand x #b10)", "(bvnot y)"])

    atom =
      one_of([
        constant("u"),
        map({member_of(["=", "bvult"]), vector, vector}, fn {r, s, t} -> "(#{r} #{s} #{t})" end)
      ])

    formula =
      tree(atom, fn inner ->
        one_of([
          map(inner, &"(not #{&1})"),
          map({member_of(["and", "or", "xor"]), inner, inner}, fn {c, l, r} ->
            "(#{c} #{l} #{r})"
          end)
        ])
      end)

    map(list_of(formula, min_length: 1, max_length: 4), fn assertions ->
      """
      (set-logic QF_BV)
      (declare-const x (_ BitVec 2))
      (declare-const y (_ BitVec 2))
      (declare-const u Bool)
      #{Enum.map_join(assertions, "\n", &"(assert #{&1})")}
      (check-sat)
      """
    end)
  end

  @doc "An RDF graph in Turtle with its number of distinct triples."
  @spec graph() :: StreamData.t({String.t(), non_neg_integer()})
  def graph do
    subject = member_of(["ex:a", "ex:b", "<http://other.org/c>"])

    object =
      one_of([
        subject,
        member_of([
          "\"x\"",
          "\"it's \\\"q\\\"\"",
          "\"hi\"@en",
          "42",
          "\"2020-01-01\"^^xsd:date",
          "true"
        ])
      ])

    map(
      list_of(tuple({subject, member_of(["ex:p", "ex:q"]), object}), max_length: 6),
      fn triples ->
        triples = Enum.uniq(triples)

        {"@prefix ex: <http://ex.org/> .\n@prefix xsd: <http://www.w3.org/2001/XMLSchema#> .\n" <>
           Enum.map_join(triples, "\n", fn {s, p, o} -> "#{s} #{p} #{o} ." end), length(triples)}
      end
    )
  end
end
