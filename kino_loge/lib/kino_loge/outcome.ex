defmodule KinoLoge.Outcome do
  @moduledoc """
  A `Loge.Outcome` as kinos: a Result tab with the verdict and the outcome's views,
  and an Output tab with the engine's raw output.

  The verdict is the status's name and mnemonic in its tone's colour, its
  description, and a link to the SZS ontology. `Kino.Render` is implemented for
  `Loge.Outcome` through `kino/1`.
  """

  alias Loge.{Diagnostic, Outcome, Range, Verdict}

  @doc "The kinos an outcome is shown as."
  @spec kino(Outcome.t()) :: Kino.Layout.t()
  def kino(%Outcome{} = outcome) do
    Kino.Layout.tabs(
      Result:
        Kino.Layout.grid([verdict(Verdict.of(outcome.szs)) | Enum.map(outcome.views, &view/1)]),
      Output: Kino.Text.new(outcome.raw)
    )
  end

  @doc "The colour a tone is drawn in."
  @spec color(Outcome.tone()) :: String.t()
  def color(:positive), do: "#1e8449"
  def color(:negative), do: "#c0392b"
  def color(:neutral), do: "#5d6d7e"

  defp verdict(%Verdict{} = verdict) do
    Kino.Layout.grid([
      label("#{verdict.name} (#{verdict.mnemonic})", verdict.tone),
      Kino.Text.new(verdict.description),
      Kino.Markdown.new("[SZS ontology](#{verdict.source})")
    ])
  end

  defp view({:text, text, _language}), do: Kino.Text.new(text)
  defp view({:badge, text, tone}), do: label(text, tone)

  defp view({:table, columns, rows}),
    do: Kino.DataTable.new(Enum.map(rows, &row(columns, &1)), keys: columns)

  defp view({:models, models}), do: Kino.Tree.new(models)
  defp view({:graph, dot}), do: Kino.Text.new(dot)

  defp view({:diagnostics, diagnostics}),
    do: Kino.Markdown.new(Enum.map_join(diagnostics, "\n", &item/1))

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
