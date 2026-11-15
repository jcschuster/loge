defmodule Loge.Shex.Languages.Shexc do
  @time_limit 10

  @moduledoc """
  ShEx schemas in ShExC as a `Loge.Language`, checked by rudof
  (`Rudof.Session.check_shex/3`): syntax, references to shapes the schema does not
  have, and negative cycles; positions as `Loge.Shex.Messages` reads them.

  Checking a schema fetches what its `IMPORT`s name, and rudof sets no time limit on
  that, so the check runs in a `Loge.Peer` and is stopped after #{@time_limit}
  seconds; the analysis then holds no diagnostic. An `IMPORT` is resolved by rudof,
  not against the sources of a notebook: the language has no includes. The analysis
  has no `native` and takes no options.
  """

  @behaviour Loge.Language

  alias Loge.Shex.{Messages, Runner}

  @impl true
  def id, do: :shex

  @impl true
  def label, do: "ShExC"

  @impl true
  def extensions, do: [".shex"]

  @impl true
  def editor_language, do: "shex"

  @impl true
  def include_names(source) when is_binary(source), do: []

  @impl true
  def analyze(source, _options) when is_binary(source) do
    diagnostics =
      case Loge.Peer.call(Runner, :check, [source], timeout: @time_limit * 1000) do
        {:ok, {:ok, {true, _account}}} -> []
        {:ok, {:ok, {false, account}}} -> [Messages.diagnostic(account, source)]
        {:ok, {:error, {:rudof, message}}} -> [Messages.diagnostic(message, source)]
        {:error, :timeout} -> []
      end

    %Loge.Analysis{language: :shex, source: source, diagnostics: diagnostics, native: nil}
  end
end
