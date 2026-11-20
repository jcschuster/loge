defmodule Loge.Tptp.VerificationTest do
  use ExUnit.Case, async: true

  import Loge.Tptp.Verification

  alias Loge.Tptp.Engines.{Clausify, Dimacs, Fof, Ground, Smtlib, Tff, Thf, Untyped}

  @moduletag :verification
  @moduletag timeout: :infinity

  setup_all do
    %{root: library!()}
  end

  defp status(root, forms, engines, judge) do
    check(problems(root, forms), engines, &verdict(judge.(&2), &1.expected), root)
  end

  defp differential(root, forms, engine, tool) do
    check(
      problems(root, forms),
      [engine],
      fn problem, output -> verdict(vampire(output), reference(problem.text, tool)) end,
      root
    )
  end

  defp reference(problem, tool) do
    with {:ok, result} <- AtpClient.SystemOnTptp.process_problem(problem, tool),
         {:ok, file, _diagnostics} <- AtpClient.Result.formulae(result) do
      file |> Tptp.Printer.Canonical.to_iodata() |> IO.iodata_to_binary() |> vampire()
    else
      _no_output -> :undecided
    end
  end

  describe "status: the recorded status of the input predicts the answer on the output" do
    @describetag :status

    for {name, forms, engines, judge} <- [
          {"Clausify under Vampire", ["+"], [Clausify], &vampire/1},
          {"Fof under Vampire", ["-"], [Fof], &vampire/1},
          {"Tff under Vampire", ["+", "-"], [Tff], &vampire/1},
          {"Thf under Vampire", ["+", "-", "_"], [Thf], &vampire/1},
          {"Untyped under Vampire", ["_"], [Untyped], &vampire/1},
          {"Ground under Vampire", ["-"], [Ground], &vampire/1},
          {"Ground and Dimacs under z3", ["-"], [Ground, Dimacs], &z3_dimacs/1},
          {"Smtlib under z3", ["+", "-", "_"], [Smtlib], &z3_smtlib/1}
        ] do
      test name, %{root: root} do
        tally = status(root, unquote(forms), unquote(engines), unquote(Macro.escape(judge)))
        report(unquote(name), tally)
        assert tally.disagree == []
      end
    end
  end

  describe "differential: the reference tool's output has the status of ours under Vampire" do
    @describetag :differential

    test "Clausify against ECNF", %{root: root} do
      tally = differential(root, ["+"], Clausify, "ECNF")
      report("Clausify against ECNF", tally)
      assert tally.disagree == []
    end

    test "Ground against EGround", %{root: root} do
      tally = differential(root, ["-"], Ground, "EGround")
      report("Ground against EGround", tally)
      assert tally.disagree == []
    end
  end
end
