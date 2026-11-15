defmodule KinoLoge.Outcome do
  @moduledoc """
  A `Loge.Outcome` as kinos: a Result tab with the verdict, the outcome's views and
  its output, and an Output tab with the engine's raw output. Raw output and text without a language are shown as a terminal shows
  them, in a monospace font; text in a language is highlighted by `KinoLoge.Code`; a
  graph view is drawn by `Kino.Mermaid`. The output is titled with its language's
  label, and is plain text when its language has no grammar or is not installed.

  The verdict is the status's name, with its mnemonic if it has one, in its tone's
  colour; its description and legend if it has them; and a link to the SZS ontology for
  a value of it. `Kino.Render` is implemented for `Loge.Outcome` through `kino/1`.
  """

  alias Loge.{Diagnostic, Outcome, Range, Verdict}

  @doc "The kinos an outcome is shown as."
  @spec kino(Outcome.t()) :: Kino.Layout.t()
  def kino(%Outcome{} = outcome) do
    Kino.Layout.tabs(
      Result:
        Kino.Layout.grid([verdict(outcome) | Enum.map(outcome.views, &view/1)] ++ output(outcome)),
      Output: Kino.Text.new(outcome.raw, terminal: true)
    )
  end

  @doc "The colour a tone is drawn in."
  @spec color(Outcome.tone()) :: String.t()
  def color(:positive), do: "#1e8449"
  def color(:negative), do: "#c0392b"
  def color(:neutral), do: "#5d6d7e"

  defp verdict(%Outcome{status: status, problem: problem}) do
    verdict = Verdict.of(status, problem)

    Kino.Layout.grid(
      [label(name(verdict), verdict.tone)] ++
        text(verdict.description) ++ text(verdict.legend) ++ link(verdict.source)
    )
  end

  defp name(%Verdict{name: name, mnemonic: nil}), do: name
  defp name(%Verdict{name: name, mnemonic: mnemonic}), do: "#{name} (#{mnemonic})"

  defp text(nil), do: []
  defp text(text), do: [Kino.Text.new(text)]

  defp link(nil), do: []
  defp link(source), do: [Kino.Markdown.new("[SZS ontology](#{source})")]

  defp output(%Outcome{output: nil}), do: []

  defp output(%Outcome{output: %Loge.Source{language: id, text: text}}) do
    case Loge.Registry.language(id) do
      {:ok, language} ->
        [view({:titled, language.label(), {:text, text, language.editor_language()}})]

      :error ->
        [view({:titled, Atom.to_string(id), {:text, text, nil}})]
    end
  end

  defp view({:text, text, nil}), do: Kino.Text.new(text, terminal: true)
  defp view({:text, text, language}), do: KinoLoge.Code.new(text, language)
  defp view({:badge, text, tone}), do: label(text, tone)

  defp view({:table, columns, rows}),
    do: Kino.DataTable.new(Enum.map(rows, &row(columns, &1)), keys: columns)

  defp view({:models, models}), do: Kino.Tree.new(models)
  defp view({:graph, mermaid}), do: Kino.Mermaid.new(mermaid)

  defp view({:diagnostics, diagnostics}),
    do: Kino.Markdown.new(Enum.map_join(diagnostics, "\n", &item/1))

  defp view({:titled, title, view}),
    do: Kino.Layout.grid([Kino.Text.new(title, style: [font_weight: :bold]), view(view)])

  defp label(text, tone), do: Kino.Text.new(text, style: [color: color(tone), font_weight: :bold])

  defp row(columns, values), do: columns |> Enum.zip(values) |> Map.new()

  defp item(%Diagnostic{range: %Range{line: line, column: column}} = diagnostic) do
    at = if column, do: "#{line}:#{column}", else: "#{line}"
    "- **#{diagnostic.severity}** #{at} `#{diagnostic.code}` #{diagnostic.message}"
  end
end

defimpl Kino.Render, for: Loge.Outcome do
  def to_livebook(outcome), do: outcome |> KinoLoge.Outcome.kino() |> Kino.Render.to_livebook()
end
