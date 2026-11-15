defmodule Loge.Turtle.Language do
  @moduledoc """
  RDF in Turtle as a `Loge.Language`, read by rudof (`Rudof.Session.read_data/3`).

  The reader reports its first error (`Loge.Turtle.Messages`). Reading runs in this
  node: it ends, and it reads nothing but the source. It costs about 176 ms of CPU
  whatever the source's size (OUTLINE §6). Turtle has no includes; the analysis has no
  `native` and takes no options.
  """

  @behaviour Loge.Language

  alias Loge.Turtle.Messages

  @impl true
  def id, do: :turtle

  @impl true
  def label, do: "Turtle"

  @impl true
  def extensions, do: [".ttl"]

  @impl true
  def editor_language, do: "turtle"

  @impl true
  def include_names(source) when is_binary(source), do: []

  @impl true
  def analyze(source, _options) when is_binary(source) do
    read = Rudof.Session.with_session(&Rudof.Session.read_data(&1, source, format: :turtle))

    diagnostics =
      case read do
        :ok -> []
        {:error, %Rudof.Error{message: message}} -> [Messages.diagnostic(message, source)]
      end

    %Loge.Analysis{language: :turtle, source: source, diagnostics: diagnostics, native: nil}
  end
end
