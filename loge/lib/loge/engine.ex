defmodule Loge.Engine do
  @moduledoc """
  Performs one task on inputs of one or more languages, as `task/0` declares:

    * `:solve`: the outcome answers the question the source states, as a prover, a
      solver or an interpreter does.
    * `:check`: the input is a derivation or a structure, and the outcome says whether
      it is what it claims to be, `:verified_good` or `:verified_bad` where a verifier
      of the TPTP World gives it.
    * `{:translate, to, preserves}`: the outcome's `output` is a source in the
      language `to`, related to the input by the SZS status `preserves`, with the input
      as the axioms Ax and the output as the conjecture C. A successful run has
      `szs: preserves`; an input outside the fragment the translation is defined on
      gives `szs: :inappropriate`, a `{:diagnostics, …}` view naming what lies outside,
      and no output.

  A tool that does several of these is several engines.

  `run/2` returns `{:ok, outcome}` when the engine produced a verdict, including
  no-success statuses such as a timeout, and `{:error, reason}` when no verdict was
  obtained.

  ## Cancellation

  The death of the process calling `run/2` aborts the run. An engine releases what it
  holds outside the BEAM (OS processes, connections, remote jobs) when that happens.
  `Loge.Run.async/1` relies on this.
  """

  @typedoc "An SZS status a translation preserves between its input, as Ax, and its output, as C."
  @type relation ::
          :equivalent
          | :equi_satisfiable
          | :satisfiability_preserving
          | :unsatisfiability_preserving
          | :theorem

  @typedoc "What an engine does with its input: solve it, check it, or translate it into the language `to`."
  @type task :: :solve | :check | {:translate, to :: atom(), relation()}

  @typedoc """
  The names a generated `Loge.run!/3` call refers to: `:includes`, the include names of
  the source, each passed as the variable of that name where it is one; `:bind`, the
  variable the outcome is bound to.
  """
  @type references :: [includes: [String.t()], bind: String.t()]

  @doc "The engine's id, such as `:clingo`; unique among registered engines."
  @callback id() :: atom()

  @doc "The name shown to users."
  @callback label() :: String.t()

  @doc "The ids of the languages it accepts."
  @callback languages() :: [atom()]

  @doc "The one task the engine performs."
  @callback task() :: task()

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
  The `:includes` option holds the `t:Loge.Language.includes/0` the input may include;
  with those the input carries, they are `Loge.Source.closure/2`.
  """
  @callback run(Loge.Input.t(), keyword()) :: {:ok, Loge.Outcome.t()} | {:error, term()}

  @doc "A sentence describing an error `run/2` or `verify/1` returned."
  @callback format_error(reason :: term()) :: String.t()

  @doc """
  The Elixir a notebook evaluates for a run: one `Loge.run!/3` call with named
  options, which needs nothing but `loge` and the engine's package.

  `input` is the source text, or an atom naming the variable that holds the input.
  Raises `ArgumentError` when `:bind` is not a variable name.

      iex> Loge.Engine.to_source(MyEngine, "p.", time_limit: 5)
      ~s|Loge.run!(MyEngine, "p.", time_limit: 5)|

      iex> Loge.Engine.to_source(MyEngine, "p.", [], bind: "result")
      ~s|result = Loge.run!(MyEngine, "p.", [])|

      iex> Loge.Engine.to_source(MyEngine, :result, models: 1)
      ~s|Loge.run!(MyEngine, result, models: 1)|

      iex> Loge.Engine.to_source(MyEngine, "include('defs').", [], includes: ["defs", "Axioms/SET001+0.ax"])
      ~s|Loge.run!(MyEngine, "include('defs').", includes: %{"defs" => defs})|
  """
  @spec to_source(module(), binary() | atom(), keyword(), references()) :: binary()
  def to_source(engine, input, options, references \\ [])
      when (is_binary(input) or is_atom(input)) and is_list(options) do
    references = Keyword.validate!(references, [:bind, includes: []])
    options = options ++ Loge.Variable.includes(references[:includes])

    quote(do: Loge.run!(unquote(engine), unquote(quoted(input)), unquote(options)))
    |> Loge.Variable.bind(references[:bind])
    |> Macro.to_string()
  end

  defp quoted(text) when is_binary(text), do: text
  defp quoted(variable) when is_atom(variable), do: Macro.var(variable, nil)
end
