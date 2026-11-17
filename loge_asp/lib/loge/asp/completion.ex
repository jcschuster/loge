defmodule Loge.Asp.Completion do
  @moduledoc """
  Clark's completion of a ground program of normal rules, choice rules and
  constraints, as clauses.

  A rule `a :- B` is the clause that `a` holds when `B` does, and a constraint the
  clause that its body does not hold. Every atom is supported: it implies the
  disjunction of the bodies of the rules with it in their head, a choice rule's as a
  normal rule's, so an atom in no head is false. A body of several literals is named
  by a new variable, numbered after the atoms, that implies each of them.

  The models of the completion, restricted to the atoms, are the supported models of
  the program. They are its answer sets when the program is tight, that is, when no
  atom depends on itself through positive body literals (Fages 1994, "Consistency of
  Clark's completion and existence of stable models"); `clauses/1` gives the atoms of
  such a loop instead of clauses.

      iex> Loge.Asp.Completion.clauses([{[1], :choice, []}, {[2], :disjunction, [1, -3]}])
      {:ok, [[2, -1, 3], [-4, 1], [-4, -3], [-2, 4], [-3]], 4}
  """

  alias Loge.Asp.Aspif

  @typedoc "A rule: the atoms of its head, none for a constraint and one unless it is a choice; and its body."
  @type rule :: {[pos_integer()], :disjunction | :choice, [Aspif.literal()]}

  @typedoc "A disjunction of literals."
  @type clause :: [Aspif.literal()]

  @doc """
  The clauses of the completion and the number of variables they are over, or the
  atoms of a positive loop.
  """
  @spec clauses([rule()]) :: {:ok, [clause()], non_neg_integer()} | {:loop, [pos_integer()]}
  def clauses(rules) do
    case loop(rules) do
      nil -> completion(rules, atoms(rules))
      atoms -> {:loop, atoms}
    end
  end

  defp completion(rules, atoms) do
    {supports, variables} = Enum.map_reduce(rules, atoms, &support/2)
    implications = for {[head], :disjunction, body} <- rules, do: [head | negated(body)]
    constraints = for {[], _kind, body} <- rules, do: negated(body)
    definitions = Enum.flat_map(supports, fn {_heads, _support, definition} -> definition end)

    supported =
      for atom <- 1..atoms//1,
          supports = for({heads, support, _definition} <- supports, atom in heads, do: support),
          :holds not in supports,
          do: [-atom | supports]

    {:ok, implications ++ constraints ++ definitions ++ supported, variables}
  end

  defp support({[], _kind, _body}, last), do: {{[], :holds, []}, last}
  defp support({heads, _kind, []}, last), do: {{heads, :holds, []}, last}
  defp support({heads, _kind, [literal]}, last), do: {{heads, literal, []}, last}

  defp support({heads, _kind, body}, last),
    do: {{heads, last + 1, Enum.map(body, &[-(last + 1), &1])}, last + 1}

  defp negated(body), do: Enum.map(body, &(-&1))

  defp atoms(rules) do
    rules
    |> Enum.flat_map(fn {heads, _kind, body} -> heads ++ Enum.map(body, &abs/1) end)
    |> Enum.max(fn -> 0 end)
  end

  defp loop(rules) do
    edges =
      for {heads, _kind, body} <- rules, head <- heads, reduce: %{} do
        edges -> Map.update(edges, head, positive(body), &(positive(body) ++ &1))
      end

    edges
    |> Map.keys()
    |> Enum.reduce_while(MapSet.new(), fn atom, done ->
      case visit(atom, edges, [], done) do
        {:loop, _atoms} = loop -> {:halt, loop}
        done -> {:cont, done}
      end
    end)
    |> case do
      {:loop, atoms} -> atoms
      _done -> nil
    end
  end

  defp visit(atom, edges, path, done) do
    cond do
      atom in path -> {:loop, Enum.reverse([atom | Enum.take_while(path, &(&1 != atom))])}
      atom in done -> done
      true -> visit_all(Map.get(edges, atom, []), edges, [atom | path], done, atom)
    end
  end

  defp visit_all([], _edges, _path, done, atom), do: MapSet.put(done, atom)

  defp visit_all([next | rest], edges, path, done, atom) do
    case visit(next, edges, path, done) do
      {:loop, _atoms} = loop -> loop
      done -> visit_all(rest, edges, path, done, atom)
    end
  end

  defp positive(body), do: Enum.filter(body, &(&1 > 0))
end
