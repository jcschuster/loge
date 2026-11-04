defmodule Loge.Engine do
  @moduledoc """
  Something that solves inputs of one or more languages: a prover, a solver, an
  interpreter.

  `run/2` returns `{:ok, outcome}` when the engine produced a verdict, including
  no-success statuses such as a timeout, and `{:error, reason}` when no verdict was
  obtained.

  ## Cancellation

  The death of the process calling `run/2` aborts the run. An engine releases what it
  holds outside the BEAM (OS processes, connections, remote jobs) when that happens.
  `Loge.Run.async/1` relies on this.
  """

  @doc "The engine's id, such as `:clingo`."
  @callback id() :: atom()

  @doc "The name shown to users."
  @callback label() :: String.t()

  @doc "The ids of the languages it accepts."
  @callback languages() :: [atom()]

  @doc "Settings that hold across runs, such as credentials and binary paths."
  @callback config_schema() :: [Loge.Config.Field.t()]

  @doc """
  Makes `settings`, keys of `config_schema/0`, the engine's settings for later runs.
  A run's own options still take precedence.
  """
  @callback configure(settings :: keyword()) :: :ok

  @doc "Checks with the given settings that the engine can be reached."
  @callback verify(keyword()) :: :ok | {:error, term()}

  @doc "Options chosen per run."
  @callback controls() :: [Loge.Control.t()]

  @doc """
  Runs the engine on an input with the control values and settings in the options.
  The `:includes` option holds the `t:Loge.Language.includes/0` the input may include.
  """
  @callback run(Loge.Input.t(), keyword()) :: {:ok, Loge.Outcome.t()} | {:error, term()}

  @doc "A sentence describing an error `run/2` or `verify/1` returned."
  @callback format_error(reason :: term()) :: String.t()

  @doc """
  The Elixir a notebook evaluates for a run: one `Loge.run!/3` call with named
  options, which needs nothing but `loge` and the engine's package.

  `includes` are the include names of the source (`c:Loge.Language.include_names/1`).
  Each one that is a variable name (`Loge.Variable.parse/1`) is passed under
  `:includes` as that variable; the others are left to the language to resolve.

      iex> Loge.Engine.to_source(MyEngine, "p.", time_limit_sec: 5)
      ~s|Loge.run!(MyEngine, "p.", time_limit_sec: 5)|

      iex> Loge.Engine.to_source(MyEngine, "include('defs').", [], ["defs", "Axioms/SET001+0.ax"])
      ~s|Loge.run!(MyEngine, "include('defs').", includes: %{"defs" => defs})|
  """
  @spec to_source(module(), binary(), keyword(), [String.t()]) :: binary()
  def to_source(engine, source, options, includes \\ [])
      when is_binary(source) and is_list(options) and is_list(includes) do
    options = options ++ includes_option(includes)

    quote(do: Loge.run!(unquote(engine), unquote(source), unquote(options)))
    |> Macro.to_string()
  end

  defp includes_option(names) do
    case for {:ok, variable} <- names |> Enum.uniq() |> Enum.map(&Loge.Variable.parse/1),
             do: {Atom.to_string(variable), Macro.var(variable, nil)} do
      [] -> []
      pairs -> [includes: {:%{}, [], pairs}]
    end
  end
end
