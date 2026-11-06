defmodule Loge.Tptp.Engines.Isabelle do
  @moduledoc """
  A THF problem checked by an Isabelle server, over `AtpClient.Isabelle.query/2`.

  Each formula becomes a lemma closed by the `:proof_method` control; the outcome's
  table lists every lemma with its status, and its status is the weakest of them.
  Options are those of `AtpClient.Isabelle.query/2`.

  The server is the configured one when a `:password` is set, in the options or the
  `:atp_client` environment, and the node's local server otherwise
  (`Loge.Tptp.IsabelleServer`), started on first use, so no setting is required. Every run opens a session of its
  own; a cancelled run closes it, which aborts the check on the server.
  """

  @behaviour Loge.Engine

  alias AtpClient.Isabelle
  alias AtpClient.Result
  alias Loge.Control
  alias Loge.Tptp.{Backend, IsabelleServer}

  @proof_methods [
    "by auto",
    "by simp",
    "by blast",
    "by metis",
    "by force",
    "by fast",
    "by linarith",
    "by presburger",
    "by arith",
    "by smt",
    "by algebra",
    "by clarsimp",
    "by safe",
    "try0 oops",
    "try oops",
    "sledgehammer oops",
    "nitpick oops",
    "nitpick[satisfy] oops",
    "sledgehammer nitpick nitpick[satisfy] oops"
  ]

  @filesystem_errors [:enoent, :eacces, :eisdir, :enotdir, :erofs, :enospc, :eperm]

  @impl true
  def id, do: :isabelle

  @impl true
  def label, do: "Isabelle"

  @impl true
  def languages, do: [:tptp]

  @impl true
  def config_schema do
    for field <- Backend.config_schema(Isabelle), do: %{field | required?: false}
  end

  @impl true
  def configure(settings), do: Backend.configure(Isabelle, settings)

  @impl true
  def verify(options) do
    with {:ok, options} <- server(options), do: Isabelle.verify(options)
  end

  @impl true
  def controls do
    [
      %Control{
        key: :proof_method,
        type: :text,
        label: "Proof method",
        choices: @proof_methods,
        default: "by auto"
      }
    ]
  end

  @impl true
  def run(input, options) do
    with {:ok, input, options} <- Backend.prepare(input, options),
         {:ok, options} <- server(options) do
      input |> Isabelle.query(options) |> outcome()
    end
  end

  @impl true
  def format_error(posix) when posix in @filesystem_errors do
    "Isabelle could not write its theory files (#{:file.format_error(posix)}). " <>
      "Check that the configured local_dir exists and is writable."
  end

  def format_error(:isabelle_not_found) do
    "No Isabelle server is configured and no isabelle executable was found. " <>
      "Set the server's password, or put isabelle on PATH or set ISABELLE_TOOL."
  end

  def format_error(reason), do: Backend.format_error(reason)

  defp server(options) do
    if AtpClient.Config.fetch(:isabelle, :password, nil, options) do
      {:ok, options}
    else
      with {:ok, connection} <- IsabelleServer.connection(),
           do: {:ok, Keyword.merge(options, connection)}
    end
  end

  defp outcome({:ok, %Result{details: %{lemmas: lemmas}}} = query),
    do: Backend.outcome(query, id(), [{:table, ["Lemma", "Status"], rows(lemmas)}])

  defp outcome(query), do: Backend.outcome(query, id())

  defp rows(lemmas), do: Enum.map(lemmas, &[&1.name, &1.status])
end
