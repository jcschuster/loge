defmodule Loge.Tptp.InputTest do
  use ExUnit.Case, async: true

  test "a Tptp.File is its source, in TPTP" do
    {:ok, file, []} = Tptp.from_string("fof(a, axiom, p).")

    assert IO.iodata_to_binary(Loge.Input.to_iodata(file)) == "fof(a, axiom, p)."
    assert Loge.Input.language(file) == :tptp
  end

  test "a Tptp.Unit is its statements, in TPTP" do
    {:ok, unit, _diagnostics} = Tptp.Unit.from_string("fof(a, axiom, p).")

    assert IO.iodata_to_binary(Loge.Input.to_iodata(unit)) ==
             IO.iodata_to_binary(AtpClient.Input.to_iodata(unit))

    assert Loge.Input.language(unit) == :tptp
  end
end
