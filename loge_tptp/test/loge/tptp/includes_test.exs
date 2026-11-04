defmodule Loge.Tptp.IncludesTest do
  use ExUnit.Case, async: true

  alias Loge.Tptp.Includes

  @library {Tptp.Resolver.Map, files: %{"Axioms/SET001+0.ax" => "fof(lib, axiom, s)."}}

  test "an input without includes is sent as it is" do
    assert Includes.input("include('Axioms/SET001+0.ax').", %{}, @library) ==
             {:ok, "include('Axioms/SET001+0.ax')."}
  end

  test "an input with includes is sent with every include inlined" do
    defs = Loge.source(:tptp, "fof(a, axiom, p).")
    source = "include('defs').\ninclude('Axioms/SET001+0.ax').\nfof(b, conjecture, p)."

    assert {:ok, %Tptp.Unit{} = unit} = Includes.input(source, %{"defs" => defs}, @library)

    assert IO.iodata_to_binary(Loge.Input.to_iodata(unit)) ==
             "fof(a, axiom, p).\nfof(lib, axiom, s).\nfof(b, conjecture, p).\n"
  end

  test "an include that cannot be resolved is an error" do
    defs = Loge.source(:tptp, "fof(a, axiom, p).")

    assert {:error, {:unresolved_includes, [%Tptp.Diagnostic{code: "TPTP0601"}]}} =
             Includes.input("include('defs'). include('nope').", %{"defs" => defs}, @library)
  end
end
