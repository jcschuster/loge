defmodule Loge do
  @moduledoc """
  One interface to logic engines: sources in, an outcome out. An engine solves a
  source, checks one, or translates it into another language under a stated semantic
  relation (`Loge.Engine`); a run's outcome can be the input of the next.

  A language package implements `Loge.Language`, `Loge.Analyzer` and `Loge.Engine`
  and registers its modules; a consumer such as a smart cell or an agent discovers
  them through `Loge.Registry` and runs them under `Loge.Run`.

  A package registers its modules when it starts:

      def start(_type, _args) do
        Enum.each([MyLang.Language, MyLang.Engine], &(:ok = Loge.register(&1)))
        Supervisor.start_link([], strategy: :one_for_one)
      end

  Modules can also be listed in the application environment, which is read when
  `:loge` starts:

      config :loge, languages: [MyLang.Language], engines: [MyLang.Engine], analyzers: []
  """

  @doc """
  Source text in a language, for another cell to include or run. See `Loge.Source`.

  The `:includes` option holds the sources the text includes, by the names it uses
  (`t:Loge.Language.includes/0`).

      iex> Loge.source(:tptp, "fof(a, axiom, p).")
      %Loge.Source{language: :tptp, text: "fof(a, axiom, p)."}
  """
  @spec source(atom(), binary(), includes: Loge.Language.includes()) :: Loge.Source.t()
  def source(language, text, options \\ []) when is_atom(language) and is_binary(text) do
    [includes: includes] = Keyword.validate!(options, includes: %{})
    %Loge.Source{language: language, text: text, includes: includes}
  end

  @doc """
  Every diagnostic about `source`: those of `c:Loge.Language.analyze/2`, then those
  of the analyzers registered for the language.

  Options other than `:analyzers` go to `analyze/2`, such as `:includes` and `:roles`;
  `:analyzers` are the options of `Loge.Analyzer.run_all/3`.
  """
  @spec lint(module(), binary(), keyword()) :: [Loge.Diagnostic.t()]
  def lint(language, source, options) do
    {analyzer_options, options} = Keyword.pop(options, :analyzers, [])
    analysis = language.analyze(source, options)
    analyzers = Loge.Registry.analyzers_for(language.id())

    findings =
      for {_id, diagnostics} when is_list(diagnostics) <-
            Loge.Analyzer.run_all(analysis, analyzers, analyzer_options),
          diagnostic <- diagnostics,
          do: diagnostic

    analysis.diagnostics ++ findings
  end

  @doc """
  Runs `engine` on `input` and returns the outcome, raising `Loge.Error` with the
  engine's description of the failure otherwise. This is the call
  `Loge.Engine.to_source/4` generates.

  The options are the engine's roles (`c:Loge.Engine.roles/0`), its controls
  (`c:Loge.Engine.controls/0`), its settings (`c:Loge.Engine.config_schema/0`) and
  `:includes`. Raises `ArgumentError` for any other key, for a required role that is
  missing, for an input or a role's value in a language the engine or the role
  does not read, and for an input that is the outcome of a translation without an
  output, naming its status and what its diagnostics say: a pipeline stops at the
  translation that did not translate instead of running on nothing.
  """
  @spec run!(module(), Loge.Input.t(), keyword()) :: Loge.Outcome.t()
  def run!(engine, input, options) when is_list(options) do
    check_translated!(input)
    check_language!(inspect(engine), engine.languages(), Loge.Input.language(input))
    check_options!(engine, Keyword.keys(options))
    Enum.each(engine.roles(), &check_role!(engine, &1, options))

    case engine.run(input, options) do
      {:ok, %Loge.Outcome{} = outcome} -> outcome
      {:error, reason} -> raise Loge.Error, engine: engine, reason: reason
    end
  end

  defp check_translated!(%Loge.Outcome{problem: :translation, output: nil} = outcome) do
    reasons =
      for {:diagnostics, diagnostics} <- outcome.views,
          diagnostic <- diagnostics,
          do: "\nline #{diagnostic.range.line}: #{diagnostic.message}"

    raise ArgumentError,
          "the input is a translation by #{inspect(outcome.engine)} that gave no output " <>
            "(#{Loge.Status.name(outcome.status)})" <> Enum.join(reasons)
  end

  defp check_translated!(_input), do: :ok

  defp check_language!(_reader, _languages, nil), do: :ok

  defp check_language!(reader, languages, language) do
    unless language in languages do
      raise ArgumentError, "#{reader} reads #{inspect(languages)}, not #{inspect(language)}"
    end
  end

  defp check_role!(engine, %Loge.Role{key: key} = role, options) do
    case Keyword.fetch(options, key) do
      {:ok, value} ->
        reader = "the role #{inspect(key)} of #{inspect(engine)}"
        check_language!(reader, role.languages, Loge.Input.language(value))

      :error when role.required? ->
        raise ArgumentError, "#{inspect(engine)} needs the role #{inspect(key)} (#{role.label})"

      :error ->
        :ok
    end
  end

  defp check_options!(engine, keys) do
    known =
      Enum.map(engine.roles(), & &1.key) ++
        Enum.map(engine.controls(), & &1.key) ++
        Enum.map(engine.config_schema(), & &1.key) ++ [:includes]

    case Enum.uniq(keys) -- known do
      [] ->
        :ok

      unknown ->
        raise ArgumentError,
              "#{inspect(engine)} has no options #{inspect(unknown)}; it takes #{inspect(known)}"
    end
  end

  @doc """
  Configures `engine` with `settings` for later runs; see `c:Loge.Engine.configure/1`.
  Raises `ArgumentError` for a key the engine's `c:Loge.Engine.config_schema/0` does
  not name. This is the call the configuration cell generates.
  """
  @spec configure!(module(), keyword()) :: :ok
  def configure!(engine, settings) when is_list(settings) do
    known = Enum.map(engine.config_schema(), & &1.key)

    case Keyword.keys(settings) -- known do
      [] -> engine.configure(settings)
      unknown -> raise ArgumentError, "#{inspect(engine)} has no settings #{inspect(unknown)}"
    end
  end

  @doc """
  Registers a language, analyzer or engine module. See `Loge.Registry.register/1`.
  """
  @spec register(module()) :: :ok | {:error, Loge.Registry.error()}
  defdelegate register(module), to: Loge.Registry
end
