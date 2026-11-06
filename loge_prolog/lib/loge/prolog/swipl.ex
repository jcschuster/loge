defmodule Loge.Prolog.Swipl do
  @moduledoc """
  A fresh SWI-Prolog, the `swipl` bundled with `swi_elixir`, for one lint or one run.

  `with_session/1` starts it under `SWI.start_link/1`, loads `priv/loge.pl` (the Prolog
  half of this module) and sends what the program prints to a file that becomes the
  session's output. A `Loge.Guard` kills the session when the caller dies; `swipl`
  exits as soon as the session's Port closes, so a cancelled lint or run stops at once.

  Positions in Prolog are character offsets; `lint/2` converts them to byte offsets of
  the source.
  """

  alias Loge.{Diagnostic, Range}

  @enforce_keys [:session, :directory]
  defstruct @enforce_keys

  @typedoc "A running session and the directory holding its program and output."
  @type t :: %__MODULE__{session: pid(), directory: Path.t()}

  @typedoc "An answer: the text of each named variable's binding, in order of appearance."
  @type answer :: [{String.t(), String.t()}]

  @typedoc """
  Whether `solve/4` found every answer, stopped at the requested count, or ran out of
  time.
  """
  @type completion :: :exhausted | :more | :timeout

  @doc """
  Runs `fun` with a fresh session and stops it. Returns the result with the output
  the session printed, or why `swipl` did not start.
  """
  @spec with_session((t() -> result)) :: {:ok, result, binary()} | {:error, term()}
        when result: term()
  def with_session(fun) when is_function(fun, 1) do
    directory = Path.join(System.tmp_dir!(), "loge_prolog_#{System.unique_integer([:positive])}")
    File.mkdir_p!(directory)

    with {:ok, session} <- SWI.start_link() do
      guard =
        Loge.Guard.start(fn ->
          Process.exit(session, :kill)
          File.rm_rf(directory)
        end)

      swipl = %__MODULE__{session: session, directory: directory}
      output = Path.join(directory, "output")
      :ok = SWI.load(session, Application.app_dir(:loge_prolog, "priv/loge.pl"))
      capture = Path.join(directory, "capture.pl")
      File.write!(capture, ":- loge:capture(#{literal(output)}).\n")
      :ok = SWI.load(session, capture)
      result = fun.(swipl)
      :ok = SWI.stop(session)
      Loge.Guard.dismiss(guard)
      printed = File.read!(output)
      File.rm_rf(directory)
      {:ok, result, printed}
    end
  end

  @doc """
  The syntax errors and singleton variables of `source`, read as consulting it would
  read it, with `op/3` directives applied to the clauses after them.
  """
  @spec lint(t(), binary()) :: [Diagnostic.t()]
  def lint(%__MODULE__{} = swipl, source) when is_binary(source) do
    file = write_program(swipl, source)
    query = SWI.query(swipl.session, "loge:lint(#{literal(file)}, Findings)")
    [%{"Findings" => findings}] = Enum.take(query, 1)
    Enum.map(findings, &diagnostic(&1, source))
  end

  @doc "Consults `source` as the program the session's goals run against."
  @spec consult(t(), binary(), pos_integer()) :: :ok | {:error, term()}
  def consult(%__MODULE__{} = swipl, source, timeout) when is_binary(source) do
    SWI.load(swipl.session, write_program(swipl, source), timeout: timeout)
  end

  @doc """
  Solves `goal`, a Prolog goal as text, for at most `count` answers, `0` for all.
  Each answer may take `timeout` milliseconds. An exception the goal raises is
  `{:error, {:prolog, message}}`.
  """
  @spec solve(t(), String.t(), non_neg_integer(), pos_integer()) ::
          {:answers, [answer()], completion()} | {:error, {:prolog, String.t()}}
  def solve(%__MODULE__{} = swipl, goal, count, timeout) when is_binary(goal) do
    swipl.session
    |> SWI.query("loge:solve(#{literal(goal)}, Answer)", timeout: timeout)
    |> Enumerable.reduce({:suspend, []}, fn bindings, answers ->
      {:suspend, [answer(bindings) | answers]}
    end)
    |> pull(if count == 0, do: :all, else: count + 1)
  end

  defp pull({:suspended, answers, continue}, 1) do
    {:halted, answers} = continue.({:halt, answers})
    {:answers, Enum.reverse(answers), :more}
  end

  defp pull({:suspended, answers, continue}, remaining),
    do: continue |> next(answers) |> pull(fewer(remaining))

  defp pull({:done, answers}, _remaining), do: {:answers, Enum.reverse(answers), :exhausted}

  defp pull({:failed, :timeout, answers}, _remaining),
    do: {:answers, Enum.reverse(answers), :timeout}

  defp pull({:failed, reason, _answers}, _remaining), do: {:error, reason}

  defp fewer(:all), do: :all
  defp fewer(remaining), do: remaining - 1

  defp next(continue, answers) do
    continue.({:cont, answers})
  rescue
    error in SWI.Error -> {:failed, error.reason, answers}
  end

  defp answer(%{"Answer" => bindings}),
    do: Enum.map(bindings, fn [name, text] -> {name, text} end)

  defp diagnostic(
         {:compound, "finding", [{:atom, severity}, {:atom, code}, from, to, message]},
         source
       ) do
    start = byte_offset(source, from)
    range = Range.from_offsets(source, start, byte_offset(source, to) - start)
    Diagnostic.new(code, severity(severity), range, message)
  end

  defp severity("error"), do: :error
  defp severity("warning"), do: :warning

  defp byte_offset(source, characters), do: byte_offset(source, characters, 0)

  defp byte_offset(_source, 0, bytes), do: bytes
  defp byte_offset(<<>>, _characters, bytes), do: bytes

  defp byte_offset(<<char::utf8, rest::binary>>, characters, bytes),
    do: byte_offset(rest, characters - 1, bytes + byte_size(<<char::utf8>>))

  defp write_program(%__MODULE__{directory: directory}, source) do
    file = Path.join(directory, "program.pl")
    File.write!(file, source)
    file
  end

  defp literal(text) do
    IO.iodata_to_binary([?", Enum.map(String.to_charlist(text), &escape/1), ?"])
  end

  defp escape(?\\), do: "\\\\"
  defp escape(?"), do: "\\\""
  defp escape(?\n), do: "\\n"
  defp escape(?\t), do: "\\t"
  defp escape(char) when char < 0x20, do: "\\x#{Integer.to_string(char, 16)}\\"
  defp escape(char), do: <<char::utf8>>
end
