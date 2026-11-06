defmodule Loge.Egglog.Language do
  @moduledoc """
  egglog as a `Loge.Language`, over `Egglog.parse/1`.

  The analysis parses the program without running it, so it reports the first syntax
  error, as a `"parse_error"`, but not type errors: egglog checks types as it runs each
  command, and running may not end. The analysis has no `native` and takes no options.
  """

  @behaviour Loge.Language

  alias Loge.{Diagnostic, Range}

  @impl true
  def id, do: :egglog

  @impl true
  def label, do: "egglog"

  @impl true
  def extensions, do: [".egg"]

  @impl true
  def editor_language, do: nil

  @impl true
  def include_names(source) when is_binary(source), do: []

  @impl true
  def analyze(source, _options) when is_binary(source) do
    diagnostics =
      case Egglog.parse(source) do
        {:ok, _commands} -> []
        {:error, {:invalid_theory, message, location}} -> [diagnostic(source, message, location)]
      end

    %Loge.Analysis{language: :egglog, source: source, diagnostics: diagnostics, native: nil}
  end

  defp diagnostic(source, message, %{file: nil, start_byte: start, end_byte: stop}) do
    range = Range.from_offsets(source, start, stop - start)
    Diagnostic.new("parse_error", :error, range, text(message))
  end

  defp diagnostic(_source, message, %{file: file}),
    do: Diagnostic.new("parse_error", :error, Range.new(1), "in '#{file}': " <> text(message))

  defp text("In " <> _ = message) do
    [_location, text] = String.split(message, "\n", parts: 2)
    text
  end
end
