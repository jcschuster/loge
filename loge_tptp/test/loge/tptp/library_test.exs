defmodule Loge.Tptp.LibraryTest do
  use ExUnit.Case, async: true

  alias Loge.Library.Entry
  alias Loge.Tptp.Library

  @library {Tptp.Resolver.Map,
            files: %{
              "Axioms/SET001+0.ax" => "fof(lib, axiom, s).",
              "Axioms/SET002+0.ax" => <<0xFF>>
            }}

  test "the index holds the problems and axiom sets of the TPTP library by their include names" do
    assert %Entry{name: "Problems/PUZ/PUZ001+1.p", description: "Dreadbury Mansion"} in Library.entries()

    assert %Entry{name: "Axioms/SET007/SET007+0.ax", description: "Mizar Built-in Notions"} in Library.entries()

    assert Enum.all?(
             Library.entries(),
             &String.match?(
               &1.name,
               ~r"\A(Axioms/([^/]+/)?[^/]+\.ax|Problems/[A-Z]{3}/[^/]+\.p)\z"
             )
           )
  end

  test "read/2 gives the text of a file through the library resolver" do
    assert Library.read("Axioms/SET001+0.ax", library: @library) == {:ok, "fof(lib, axiom, s)."}
  end

  test "read/2 gives the resolver's reason for a file it cannot read" do
    assert {:error, reason} = Library.read("Axioms/SET003+0.ax", library: @library)
    assert Library.format_error(reason) == ~s("Axioms/SET003+0.ax" is not in the resolver's map)
  end

  test "read/2 refuses a file that is not UTF-8" do
    assert {:error, reason} = Library.read("Axioms/SET002+0.ax", library: @library)
    assert Library.format_error(reason) == "the file is not UTF-8 text"
  end

  test "read/2 reads nothing through a resolver that follows no include" do
    assert {:error, reason} = Library.read("Axioms/SET001+0.ax", library: Tptp.Resolver.None)

    assert Library.format_error(reason) ==
             "the library is not read: its resolver follows no include"
  end
end
