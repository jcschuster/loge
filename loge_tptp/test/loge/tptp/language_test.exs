defmodule Loge.Tptp.LanguageTest do
  use ExUnit.Case, async: true

  alias Loge.{Analysis, Diagnostic, Range}
  alias Loge.Tptp.Language

  test "describes TPTP" do
    assert Language.id() == :tptp
    assert ".p" in Language.extensions()
    assert Language.editor_language() == "tptp"
  end

  test "a clean source has no diagnostics and keeps the native analysis" do
    assert %Analysis{language: :tptp, diagnostics: [], native: %Tptp.Analysis{}} =
             Language.analyze("fof(a, conjecture, p).", [])
  end

  test "positions diagnostics in UTF-16 columns" do
    source = "/* é😀 */ fof(a, axiom, p). fof(a, conjecture, q)."
    %Analysis{diagnostics: [diagnostic]} = Language.analyze(source, [])
    %Tptp.Diagnostic{span: span} = hd(Tptp.analyze(source).diagnostics)

    assert %Diagnostic{code: "TPTP0503", range: range} = diagnostic
    assert range == Range.from_offsets(source, span.offset, span.length)
    assert range.column == String.length(binary_part(source, 0, span.offset)) + 2
  end

  test "a source that does not parse still yields an analysis" do
    assert %Analysis{diagnostics: [%Diagnostic{severity: :error, range: %Range{line: 2}} | _]} =
             Language.analyze("fof(a, conjecture, p).\nfof(b, axiom, ", [])
  end

  test "names the includes a source uses" do
    source = "include('defs').\nfof(a, axiom, p).\ninclude('Axioms/SET001+0.ax', [x])."
    assert Language.include_names(source) == ["defs", "Axioms/SET001+0.ax"]
  end

  test "names the includes of a source that does not parse to the end" do
    assert Language.include_names("include('defs').\nfof(a, axiom, ") == ["defs"]
  end

  describe "includes" do
    @library {Tptp.Resolver.Map, files: %{"Axioms/SET001+0.ax" => "fof(lib, axiom, s)."}}

    defp analyze(source, includes),
      do: Language.analyze(source, includes: includes, library: @library).diagnostics

    test "resolve from the includes and the library" do
      source = "include('defs').\ninclude('Axioms/SET001+0.ax').\nfof(b, conjecture, p)."
      defs = Loge.source(:tptp, "fof(a, axiom, p).")
      analysis = Language.analyze(source, includes: %{"defs" => defs}, library: @library)

      assert analysis.diagnostics == []
      assert %Tptp.Unit{} = analysis.native.file
    end

    test "a name in neither is an error on the include" do
      assert [%Diagnostic{code: "TPTP0601", severity: :error, range: range}] =
               analyze("fof(b, conjecture, p).\ninclude('missing').", %{})

      assert range == Range.new(2, column: 1, end_line: 2, end_column: 20)
    end

    test "a finding inside an include is placed on the include that reaches it" do
      defs = Loge.source(:tptp, "fof(a, axiom, p).\nfof(a, axiom, q).")
      outer = Loge.source(:tptp, "include('defs').")
      source = "% problem\ninclude('outer').\nfof(b, conjecture, p)."

      assert [%Diagnostic{code: "TPTP0503", range: range, message: message}] =
               analyze(source, %{"outer" => outer, "defs" => defs})

      assert range == Range.new(2, column: 1, end_line: 2, end_column: 18)
      assert message =~ ~r/^in 'outer': /
    end

    test "any Loge.Input can be included" do
      {:ok, file, []} = Tptp.from_string("fof(a, axiom, p).")
      assert analyze("include('defs'). fof(b, conjecture, p).", %{"defs" => file}) == []
    end
  end
end
