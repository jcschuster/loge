defmodule Loge.Egglog.Engines.EgglogTest do
  use ExUnit.Case, async: true

  alias Loge.{Control, Diagnostic, Outcome}
  alias Loge.Egglog.Engines.Egglog

  @math """
  (datatype Math (Num i64) (Add Math Math) (Mul Math Math))
  (rewrite (Add a b) (Add b a))
  (rewrite (Mul a (Num 1)) a)
  (let e (Add (Mul (Num 2) (Num 1)) (Num 3)))
  (run 5)
  """

  test "describes the engine" do
    assert Egglog.id() == :egglog
    assert Egglog.languages() == [:egglog]
    assert Egglog.config_schema() == []
    assert Egglog.verify([]) == :ok
    assert [%Control{key: :graph, type: :boolean, default: false}] = Egglog.controls()
  end

  test "a program that runs to its end is a success and shows its outputs" do
    assert {:ok, %Outcome{status: :success, engine: :egglog, views: [text], raw: raw}} =
             Egglog.run(@math <> "(check (= e (Add (Num 3) (Num 2))))\n(extract e)", [])

    assert raw in ["(Add (Num 3) (Num 2))\n", "(Add (Num 2) (Num 3))\n"]
    assert text == {:text, raw, nil}
  end

  test "a failed check stops the program with no, and shows egglog's message" do
    assert {:ok, %Outcome{status: :no, views: [], raw: raw}} =
             Egglog.run(@math <> "(check (= e (Num 5)))", [])

    assert raw =~ "Check failed"
  end

  test "the e-graph as a Mermaid flowchart" do
    assert {:ok, %Outcome{views: [{:graph, "flowchart TB\n" <> _}]}} =
             Egglog.run(@math, graph: true)
  end

  test "the includes of the run and those the source carries are run with it" do
    defs = Loge.source(:egglog, "(datatype M (Num i64))")

    program =
      Loge.source(:egglog, "(include \"defs\")\n(let x (Num 1))\n(extract x)",
        includes: %{"defs" => defs}
      )

    assert {:ok, %Outcome{status: :success, raw: "(Num 1)\n"}} = Egglog.run(program, [])

    assert {:ok, %Outcome{raw: "(Num 1)\n"}} =
             Egglog.run("(include \"defs\")\n(let x (Num 1))\n(extract x)",
               includes: %{"defs" => defs}
             )
  end

  test "an include no source of that name holds is an error with egglog's message" do
    assert {:error, {:egglog, message}} = Egglog.run("(include \"defs\")", [])
    assert message =~ "No such file"
  end

  test "a type error is an error with egglog's message" do
    assert {:error, {:egglog, message} = reason} =
             Egglog.run("(datatype M (Num i64))\n(let x (Num \"s\"))", [])

    assert message =~ "Expect expression"
    assert Egglog.format_error(reason) == message
  end

  test "a program that does not parse is an error carrying its diagnostics" do
    assert {:error, {:invalid_program, [%Diagnostic{code: "parse_error"}]} = reason} =
             Egglog.run(Loge.source(:egglog, "(datatype M"), [])

    assert Egglog.format_error(reason) =~ ~r/^Invalid egglog program:\nline 1: parse error/
  end

  test "Loge.run!/3 runs the engine" do
    assert %Outcome{status: :success, views: []} = Loge.run!(Egglog, @math, graph: false)
  end
end
