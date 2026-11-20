defmodule Loge.Tptp.Verification do
  @moduledoc false

  @unsatisfiable [:theorem, :unsatisfiable, :contradictory_axioms]
  @satisfiable [:countersatisfiable, :satisfiable]
  @largest 200_000
  @deadline 30_000

  @type answer :: :satisfiable | :unsatisfiable | :undecided
  @type verdict :: :agree | :disagree | :undecided
  @type problem :: %{name: String.t(), text: binary(), expected: :satisfiable | :unsatisfiable}

  @spec library!() :: Path.t()
  def library! do
    case System.fetch_env("TPTP") do
      {:ok, root} -> root
      :error -> raise "the verification suite reads the TPTP library: set TPTP to its root"
    end
  end

  @spec count() :: pos_integer()
  def count, do: String.to_integer(System.get_env("LOGE_VERIFICATION_PROBLEMS", "20"))

  @doc """
  The problems of the library in the forms `forms` (`"+"`, `"-"`, `"_"`, `"^"`) with a
  status that fixes the satisfiability of the axioms with the negated conjecture, a
  rating of at most 0.5 in the last release and at most 200 kB with their includes, in
  an order fixed by their names that spreads them across the domains.
  """
  @spec problems(Path.t(), [String.t()]) :: Enumerable.t(problem())
  def problems(root, forms) do
    root
    |> Path.join("Problems/*/*.p")
    |> Path.wildcard()
    |> Enum.filter(
      &(&1
        |> Path.basename()
        |> String.slice(6, 1)
        |> then(fn form -> form in forms end))
    )
    |> Enum.sort_by(&:erlang.phash2(Path.basename(&1)))
    |> Stream.map(&read(&1, root))
    |> Stream.reject(&is_nil/1)
  end

  defp read(path, root) do
    text = File.read!(path)
    {:ok, header, _diagnostics} = Tptp.Header.from_string(text)

    with expected when expected != nil <- expected(Tptp.Header.status(header)),
         true <- rating(header) <= 0.5,
         true <- byte_size(text) + included(text, root) <= @largest do
      %{name: Path.basename(path, ".p"), text: text, expected: expected}
    else
      _excluded -> nil
    end
  end

  defp expected(status) when status in @unsatisfiable, do: :unsatisfiable
  defp expected(status) when status in @satisfiable, do: :satisfiable
  defp expected(_status), do: nil

  defp rating(header) do
    case Regex.run(~r/\A\s*(\d\.\d+)/, Tptp.Header.get(header, "Rating") || "") do
      [_, rating] -> String.to_float(rating)
      nil -> 1.0
    end
  end

  defp included(text, root) do
    ~r/^include\('([^']+)'/m
    |> Regex.scan(text, capture: :all_but_first)
    |> Enum.sum_by(fn [name] ->
      case File.stat(Path.join(root, name)) do
        {:ok, %File.Stat{size: size}} -> size
        {:error, _reason} -> @largest
      end
    end)
  end

  @doc """
  Runs `engines` in turn on the problem, each on the output of the one before:
  `{:ok, output}`; `:outside` when one finds its input outside its fragment; or
  `:undecided` when one runs past the deadline of 30 s, as `Ground` does on a problem
  with more instances than fit in memory.
  """
  @spec translate(problem(), [module()], Path.t()) :: {:ok, String.t()} | :outside | :undecided
  def translate(problem, engines, root) do
    Enum.reduce_while(engines, {:ok, problem.text}, fn engine, {:ok, input} ->
      task = Loge.Run.async(fn -> engine.run(input, library: {Tptp.Resolver.Fs, root: root}) end)

      case Task.yield(task, @deadline) || Task.shutdown(task, :brutal_kill) do
        nil ->
          {:halt, :undecided}

        {:ok, {:ok, %Loge.Outcome{status: :inappropriate}}} ->
          {:halt, :outside}

        {:ok, {:ok, %Loge.Outcome{output: %Loge.Source{text: text}}}} ->
          {:cont, {:ok, text}}

        other ->
          raise "#{inspect(engine)} on #{problem.name}: #{inspect(other)}"
      end
    end)
  end

  @doc """
  Vampire's answer to a TPTP problem: that of its CASC portfolio, else that of its
  finite model builder. It runs here and not through an engine, to share nothing with
  the translations.
  """
  @spec vampire(String.t()) :: answer()
  def vampire(text) do
    Enum.find_value(
      [["--mode", "casc"], ["--saturation_algorithm", "fmb"]],
      :undecided,
      fn strategy ->
        output =
          run(
            "vampire",
            strategy ++ ["--input_syntax", "tptp", "-t", "10", "-m", "2000"],
            text,
            ".p"
          )

        case Regex.run(~r/SZS status (\w+)/, output, capture: :all_but_first) do
          [status] when status in ["Satisfiable", "CounterSatisfiable"] ->
            :satisfiable

          [status] when status in ["Unsatisfiable", "Theorem", "ContradictoryAxioms"] ->
            :unsatisfiable

          _other ->
            nil
        end
      end
    )
  end

  @doc "z3's answer to an SMT-LIB script, from its last line."
  @spec z3_smtlib(String.t()) :: answer()
  def z3_smtlib(text) do
    case "z3" |> run(["-T:20"], text, ".smt2") |> String.split("\n", trim: true) |> List.last() do
      "sat" -> :satisfiable
      "unsat" -> :unsatisfiable
      _other -> :undecided
    end
  end

  @doc "z3's answer to a DIMACS CNF formula."
  @spec z3_dimacs(String.t()) :: answer()
  def z3_dimacs(text) do
    output = run("z3", ["-T:20", "-dimacs"], text, ".cnf")

    cond do
      output =~ ~r/^s UNSATISFIABLE/m -> :unsatisfiable
      output =~ ~r/^s SATISFIABLE/m -> :satisfiable
      true -> :undecided
    end
  end

  defp run(executable, arguments, text, extension) do
    {:ok, exit} =
      Loge.Executable.run(executable, arguments, text,
        extension: extension,
        stderr: :merge,
        timeout: 30_000
      )

    exit.output
  end

  @doc """
  The first `count/0` problems of `problems` that `engines` translate or run past the
  deadline on, each with its verdict, of `verdict` on the problem and the output, or
  `:undecided` past the deadline: a map of `:agree`,
  `:disagree` and `:undecided` to the names of those problems, and `:outside` to the
  number of problems skipped until then as outside the fragment.
  """
  @spec check(Enumerable.t(problem()), [module()], (problem(), String.t() -> verdict()), Path.t()) ::
          %{
            agree: [String.t()],
            disagree: [String.t()],
            undecided: [String.t()],
            outside: non_neg_integer()
          }
  def check(problems, engines, verdict, root) do
    {translated, _left, outside} =
      problems
      |> Stream.map(&{&1, translate(&1, engines, root)})
      |> Enum.reduce_while({[], count(), 0}, fn
        {_problem, :outside}, {translated, left, outside} ->
          {:cont, {translated, left, outside + 1}}

        reading, {translated, 1, outside} ->
          {:halt, {[reading | translated], 0, outside}}

        reading, {translated, left, outside} ->
          {:cont, {[reading | translated], left - 1, outside}}
      end)

    translated
    |> Task.async_stream(
      fn
        {problem, :undecided} -> {problem.name, :undecided}
        {problem, {:ok, output}} -> {problem.name, verdict.(problem, output)}
      end,
      ordered: false,
      max_concurrency: 4,
      timeout: :infinity
    )
    |> Enum.reduce(%{agree: [], disagree: [], undecided: [], outside: outside}, fn
      {:ok, {name, verdict}}, tally -> Map.update!(tally, verdict, &Enum.sort([name | &1]))
    end)
  end

  @doc "The verdict of `answer` on a problem whose recorded status predicts `expected`."
  @spec verdict(answer(), answer()) :: verdict()
  def verdict(:undecided, _expected), do: :undecided
  def verdict(_answer, :undecided), do: :undecided
  def verdict(expected, expected), do: :agree
  def verdict(_answer, _expected), do: :disagree

  @spec report(String.t(), map()) :: :ok
  def report(check, tally) do
    IO.puts(
      "\n#{check}: #{length(tally.agree)} agree, #{length(tally.disagree)} disagree, " <>
        "#{length(tally.undecided)} undecided, #{tally.outside} outside the fragment" <>
        Enum.map_join([:disagree, :undecided], fn verdict ->
          if tally[verdict] == [],
            do: "",
            else: "\n  #{verdict}: #{Enum.join(tally[verdict], ", ")}"
        end)
    )
  end
end
