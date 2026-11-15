defmodule KinoLoge.OutcomeTest do
  use ExUnit.Case, async: true

  import Kino.Test

  alias Loge.{Diagnostic, Outcome, Range, Verdict}

  setup :configure_livebook_bridge

  @outcome %Outcome{status: :theorem, raw: "% SZS status Theorem\n", engine: :fake_engine}

  test "the result tab shows the verdict, the output tab the raw output" do
    %Kino.Layout{type: :tabs, info: %{labels: ["Result", "Output"]}, items: [result, output]} =
      KinoLoge.Outcome.kino(@outcome)

    assert %Kino.Layout{type: :grid, items: [verdict]} = result
    assert %Kino.Layout{items: [name, description, link]} = verdict
    assert %Kino.Text{text: "Theorem (THM)", style: [color: color, font_weight: :bold]} = name
    assert color == KinoLoge.Outcome.color(:positive)
    assert %Kino.Text{text: text} = description
    assert text == Verdict.of(:theorem, :entailment).description
    assert %Kino.Markdown{text: markdown} = link
    assert markdown =~ "(#{Verdict.of(:theorem, :entailment).source})"
    assert output == Kino.Text.new(@outcome.raw, terminal: true)
  end

  test "a verdict without a description shows its name and the link" do
    outcome = %Outcome{status: :satisfiable, problem: :satisfiability, raw: "", engine: :e}

    %Kino.Layout{items: [%Kino.Layout{items: [verdict]}, _output]} =
      KinoLoge.Outcome.kino(outcome)

    assert %Kino.Layout{items: [%Kino.Text{text: "Satisfiable (SAT)"}, %Kino.Markdown{}]} =
             verdict
  end

  test "the tone colours the name" do
    for {status, tone} <- [input_error: :negative, timeout: :neutral] do
      %Kino.Layout{items: [%Kino.Layout{items: [verdict]}, _output]} =
        KinoLoge.Outcome.kino(%{@outcome | status: status})

      %Kino.Layout{items: [%Kino.Text{style: style} | _]} = verdict
      assert style[:color] == KinoLoge.Outcome.color(tone)
    end
  end

  test "a status of Loge's own shows its name and description, without mnemonic or link" do
    outcome = %Outcome{status: :yes, raw: "", engine: :fake_engine}

    %Kino.Layout{items: [%Kino.Layout{items: [verdict]}, _output]} =
      KinoLoge.Outcome.kino(outcome)

    assert %Kino.Layout{items: [%Kino.Text{text: "Yes", style: style}, %Kino.Text{text: text}]} =
             verdict

    assert style[:color] == KinoLoge.Outcome.color(:positive)
    assert text == Loge.Status.description(:yes)
  end

  test "views follow the verdict, in order" do
    views = [
      {:text, "model", nil},
      {:text, "proof", "fake"},
      {:badge, "SAT", :neutral},
      {:table, ["Lemma", "Status"], [["a", :theorem]]},
      {:models, [%{p: true}]},
      {:graph, "flowchart TB\n  a --> b\n"},
      {:diagnostics, [Diagnostic.new("X", :warning, Range.new(2, column: 3), "careful")]},
      {:titled, "Proof", {:text, "steps", nil}}
    ]

    %Kino.Layout{items: [%Kino.Layout{items: [_verdict | kinos]}, _output]} =
      KinoLoge.Outcome.kino(%{@outcome | views: views})

    assert [
             %Kino.Text{text: "model", terminal: true},
             %Kino.JS{module: KinoLoge.Code},
             %Kino.Text{text: "SAT", style: [color: _, font_weight: :bold]},
             %Kino.JS.Live{module: Kino.Table},
             %Kino.Layout{},
             %Kino.JS{module: Kino.Mermaid},
             %Kino.Markdown{text: diagnostics},
             %Kino.Layout{type: :grid, items: [title, %Kino.Text{text: "steps"}]}
           ] = kinos

    assert %Kino.Text{text: "Proof", style: [font_weight: :bold]} = title

    assert diagnostics =~ "2:3"
    assert diagnostics =~ "careful"
  end

  test "the output follows the views, in its language" do
    outcome = %{@outcome | views: [{:badge, "done", :neutral}], output: Loge.source(:fake, "p.")}

    %Kino.Layout{items: [%Kino.Layout{items: [_verdict, _badge, output]}, _raw]} =
      KinoLoge.Outcome.kino(outcome)

    assert %Kino.Layout{items: [%Kino.Text{text: "Fake"}, %Kino.JS{module: KinoLoge.Code}]} =
             output
  end

  test "an output without a grammar, or in a language not installed, is plain text" do
    for {language, title} <- [other: "Other", nope: "nope"] do
      outcome = %{@outcome | output: Loge.source(language, "p.")}

      %Kino.Layout{items: [%Kino.Layout{items: [_verdict, output]}, _raw]} =
        KinoLoge.Outcome.kino(outcome)

      assert %Kino.Layout{items: [%Kino.Text{text: ^title}, %Kino.Text{terminal: true}]} = output
    end
  end

  test "a translation's verdict says what Ax and C stand for" do
    outcome = %Outcome{status: :equi_satisfiable, problem: :translation, raw: "", engine: :e}

    %Kino.Layout{items: [%Kino.Layout{items: [verdict]}, _raw]} = KinoLoge.Outcome.kino(outcome)

    assert %Kino.Layout{items: [_name, _description, %Kino.Text{text: legend}, _link]} = verdict
    assert legend == "Ax: the input, C: the output"
  end

  test "an outcome renders in Livebook" do
    assert %{type: :tabs, labels: ["Result", "Output"]} = Kino.Render.to_livebook(@outcome)
  end
end
