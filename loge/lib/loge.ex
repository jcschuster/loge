defmodule Loge do
  @moduledoc """
  Contracts for editing, linting and solving problems in logic languages.

  A language package implements `Loge.Language`, `Loge.Analyzer` and `Loge.Engine`
  and registers its modules; a consumer such as a smart cell discovers them through
  `Loge.Registry` and runs them under `Loge.Run`.

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
  Source text in a language, for another cell to include. See `Loge.Source`.

      iex> Loge.source(:tptp, "fof(a, axiom, p).")
      %Loge.Source{language: :tptp, text: "fof(a, axiom, p)."}
  """
  @spec source(atom(), binary()) :: Loge.Source.t()
  def source(language, text) when is_atom(language) and is_binary(text),
    do: %Loge.Source{language: language, text: text}

  @doc """
  Every diagnostic about `source`: those of `c:Loge.Language.analyze/2`, then those
  of the analyzers registered for the language.

  Options other than `:analyzers` go to `analyze/2`; `:analyzers` are the options of
  `Loge.Analyzer.run_all/3`.
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
  `Loge.Engine.to_source/3` generates.
  """
  @spec run!(module(), Loge.Input.t(), keyword()) :: Loge.Outcome.t()
  def run!(engine, input, options) do
    case engine.run(input, options) do
      {:ok, %Loge.Outcome{} = outcome} -> outcome
      {:error, reason} -> raise Loge.Error, engine: engine, reason: reason
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
