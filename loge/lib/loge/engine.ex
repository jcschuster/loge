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

  @doc "Checks with the given settings that the engine can be reached."
  @callback verify(keyword()) :: :ok | {:error, term()}

  @doc "Options chosen per run."
  @callback controls() :: [Loge.Control.t()]

  @doc "Runs the engine on an input with the control values and settings in the options."
  @callback run(Loge.Input.t(), keyword()) :: {:ok, Loge.Outcome.t()} | {:error, term()}

  @doc """
  The Elixir expression a notebook evaluates for this run: one call with named options
  that needs nothing but the engine's own package.
  """
  @callback to_source(Loge.Input.t(), keyword()) :: binary()
end
