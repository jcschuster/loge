defmodule KinoLoge.CodeTest do
  use ExUnit.Case, async: true

  import Kino.Test

  setup :configure_livebook_bridge

  test "the client gets the text and the name of its grammar" do
    kino = KinoLoge.Code.new("cnf(a, axiom, p).", "fake")

    assert %Kino.JS{module: KinoLoge.Code} = kino
    assert %{js_view: %{ref: ref, pid: pid}} = Kino.Render.to_livebook(kino)

    send(pid, {:connect, self(), %{origin: "client", ref: ref}})
    assert_receive {:connect_reply, %{text: "cnf(a, axiom, p).", language: "fake"}, %{ref: ^ref}}
  end
end
