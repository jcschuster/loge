defmodule Loge.AnalyzerTest do
  use ExUnit.Case, async: true

  alias Loge.{Analysis, Analyzer, Diagnostic, Range}
  alias Loge.Fake

  setup do
    %{analysis: %Analysis{language: :fake, source: "src", diagnostics: []}}
  end

  test "runs analyzers for the language and skips the others", %{analysis: analysis} do
    assert [
             {:fake_analyzer, [%Diagnostic{code: "FAKE0002", message: "src"}]},
             {:any_analyzer, []},
             {:other_analyzer, :skipped}
           ] =
             Analyzer.run_all(analysis, [
               Fake.Analyzer,
               Fake.AnyAnalyzer,
               Fake.OtherLanguageAnalyzer
             ])
  end

  test "passes each analyzer the options under its id", %{analysis: analysis} do
    assert [{:fake_analyzer, [%Diagnostic{message: "hi"}]}] =
             Analyzer.run_all(analysis, [Fake.Analyzer], fake_analyzer: [say: "hi"])
  end

  for {analyzer, detail} <- [
        {Fake.RaisingAnalyzer, "boom"},
        {Fake.ExitingAnalyzer, ":gone"},
        {Fake.ThrowingAnalyzer, ":ball"}
      ] do
    test "turns a failure of #{inspect(analyzer)} into one diagnostic", %{analysis: analysis} do
      id = unquote(analyzer).id()

      assert [
               {^id,
                [%Diagnostic{code: "LOGE0001", severity: :error, range: range, message: message}]}
             ] =
               Analyzer.run_all(analysis, [unquote(analyzer)])

      assert range == Range.new(1)
      assert message =~ inspect(unquote(analyzer))
      assert message =~ unquote(detail)
    end
  end
end
