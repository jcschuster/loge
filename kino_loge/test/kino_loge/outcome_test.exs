defmodule KinoLoge.OutcomeTest do
  use ExUnit.Case, async: true

  import Kino.Test

  alias Loge.{Diagnostic, Outcome, Range, Verdict}

  setup :configure_livebook_bridge

  @outcome %Outcome{szs: :theorem, raw: "% SZS status Theorem\n", engine: :fake_engine}

  test "the result tab shows the verdict, the output tab the raw output" do
    %Kino.Layout{type: :tabs, info: %{labels: ["Result", "Output"]}, items: [result, output]} =
      KinoLoge.Outcome.kino(@outcome)

    assert %Kino.Layout{type: :grid, items: [verdict]} = result
    assert %Kino.Layout{items: [name, description, link]} = verdict
    assert %Kino.Text{text: "Theorem (THM)", style: [color: color, font_weight: :bold]} = name
    assert color == KinoLoge.Outcome.color(:positive)
    assert %Kino.Text{text: text} = description
    assert text == Verdict.of(:theorem).description
    assert %Kino.Markdown{text: markdown} = link
    assert markdown =~ "(#{Verdict.of(:theorem).source})"
    assert output == Kino.Text.new(@outcome.raw)
  end

  test "the tone colours the name" do
    for {status, tone} <- [input_error: :negative, timeout: :neutral] do
      %Kino.Layout{items: [%Kino.Layout{items: [verdict]}, _output]} =
        KinoLoge.Outcome.kino(%{@outcome | szs: status})

      %Kino.Layout{items: [%Kino.Text{style: style} | _]} = verdict
      assert style[:color] == KinoLoge.Outcome.color(tone)
    end
  end

  test "an outcome without an SZS status shows only its views" do
    outcome = %Outcome{raw: "", engine: :fake_engine, views: [{:badge, "true", :positive}]}

    assert %Kino.Layout{items: [%Kino.Layout{type: :grid, items: [badge]}, _output]} =
             KinoLoge.Outcome.kino(outcome)

    assert %Kino.Text{text: "true", style: [color: _, font_weight: :bold]} = badge
  end

  test "views follow the verdict, in order" do
    views = [
      {:text, "model", nil},
      {:badge, "SAT", :neutral},
      {:table, ["Lemma", "Status"], [["a", :theorem]]},
      {:models, [%{p: true}]},
      {:graph, "digraph {}"},
      {:diagnostics, [Diagnostic.new("X", :warning, Range.new(2, column: 3), "careful")]}
    ]

    %Kino.Layout{items: [%Kino.Layout{items: [_verdict | kinos]}, _output]} =
      KinoLoge.Outcome.kino(%{@outcome | views: views})

    assert [
             %Kino.Text{text: "model"},
             %Kino.Text{text: "SAT", style: [color: _, font_weight: :bold]},
             %Kino.JS.Live{module: Kino.Table},
             %Kino.Layout{},
             %Kino.Text{text: "digraph {}"},
             %Kino.Markdown{text: diagnostics}
           ] = kinos

    assert diagnostics =~ "2:3"
    assert diagnostics =~ "careful"
  end

  test "an outcome renders in Livebook" do
    assert %{type: :tabs, labels: ["Result", "Output"]} = Kino.Render.to_livebook(@outcome)
  end
end
