defmodule Loge.Asp.Language do
  @time_limit 10

  @moduledoc """
  Answer Set Programming in clingo's input language as a `Loge.Language`.

  A source is analysed by grounding it with the `clingo` executable bundled with
  `clingo_elixir` (`clingo --solve-limit=0`, run by `Loge.Executable`), which reports
  syntax errors, unsafe variables and the grounder's warnings without searching for
  models; `Loge.Asp.Messages` reads them. Grounding that does not end is stopped after
  #{@time_limit} seconds, and the analysis then holds what clingo reported until then.
  The sources of the `:includes` option, and those they carry, are grounded with it
  (`Loge.Asp.Includes`); a finding in one is placed on the first line and names it.
  The analysis has no `native`.
  """

  @behaviour Loge.Language

  alias Loge.Asp.{Includes, Messages}

  @impl true
  def id, do: :asp

  @impl true
  def label, do: "ASP"

  @impl true
  def extensions, do: [".lp"]

  @impl true
  def editor_language, do: "asp"

  @impl true
  def include_names(source) when is_binary(source), do: Includes.names(source)

  @impl true
  def analyze(source, options) when is_binary(source) do
    includes = Loge.Source.closure(source, Keyword.get(options, :includes, %{}))

    {:ok, %Loge.Executable.Exit{output: output, file: file}} =
      Loge.Executable.run(Clingo.CLI.executable(), ["--outf=3", "--solve-limit=0"], source,
        extension: ".lp",
        files: Includes.files(includes),
        stderr: :merge,
        timeout: @time_limit * 1000
      )

    %Loge.Analysis{
      language: :asp,
      source: source,
      diagnostics: Messages.parse(output, source, file),
      native: nil
    }
  end
end
