defmodule Loge.Asp.Language do
  @time_limit 10

  @moduledoc """
  Answer Set Programming in clingo's input language as a `Loge.Language`.

  A source is analysed by grounding it with `clingo --solve-limit=0`, which reports
  syntax errors, unsafe variables and the grounder's warnings without searching for
  models; `Loge.Asp.Messages` reads them. Grounding that does not end is stopped when
  the caller dies (`Loge.Asp.Executable`), and in any case after #{@time_limit} seconds, so
  a clingo left behind by a stopped VM ends too; the analysis then holds what clingo
  reported until then. The analysis has no `native` and takes no options.
  """

  @behaviour Loge.Language

  alias Loge.Asp.{Executable, Messages}

  @impl true
  def id, do: :asp

  @impl true
  def label, do: "ASP"

  @impl true
  def extensions, do: [".lp"]

  @impl true
  def editor_language, do: nil

  @impl true
  def include_names(source) when is_binary(source), do: []

  @impl true
  def analyze(source, _options) when is_binary(source) do
    {output, _status, file} =
      Executable.run(
        source,
        ["--outf=3", "--solve-limit=0", "--time-limit=#{@time_limit}"],
        :stdout_and_stderr
      )

    %Loge.Analysis{
      language: :asp,
      source: source,
      diagnostics: Messages.parse(output, source, file),
      native: nil
    }
  end
end
