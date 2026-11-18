defmodule Mix.Tasks.Loge.Tptp.LibraryTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  @root Path.expand("../../fixtures/library", __DIR__)

  @tag :tmp_dir
  test "writes the index of a distribution's problems and axiom sets", %{tmp_dir: dir} do
    output = Path.join(dir, "library.tsv")

    assert capture_io(fn -> Mix.Task.rerun("loge.tptp.library", [@root, "--output", output]) end) ==
             "4 files indexed in #{output}\n"

    assert File.read!(output) ==
             "Axioms/SET/SET002+0.ax\tNested\n" <>
               "Axioms/SET001+0.ax\tMembership and subsets with a tab\n" <>
               "Problems/PUZ/PUZ001+1.p\tDreadbury Mansion\n" <>
               "Problems/PUZ/PUZ002-1.p\t\n"
  end

  test "needs the root of a distribution" do
    assert_raise Mix.Error, ~r/usage/, fn -> Mix.Task.rerun("loge.tptp.library", []) end
  end
end
