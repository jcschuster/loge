defmodule KinoLoge.ConfigCellTest do
  use ExUnit.Case, async: true

  import Kino.Test

  alias KinoLoge.ConfigCell

  setup :configure_livebook_bridge

  test "the client gets every engine's fields" do
    {kino, source} = start_smart_cell!(ConfigCell, %{})
    data = connect(kino)

    assert source == ":ok"

    assert [
             %{id: "fake_engine", label: "Fake engine", fields: fields},
             %{id: "second_engine", fields: []}
           ] = data.engines

    assert %{
             key: "url",
             type: "string",
             group: "connection",
             label: "URL",
             required: true,
             secret: false,
             default: "https://x",
             value: nil
           } =
             Enum.find(fields, &(&1.key == "url"))

    assert %{key: "password", secret: true} = Enum.find(fields, &(&1.key == "password"))
    assert %{key: "tls", label: "Tls"} = Enum.find(fields, &(&1.key == "tls"))
  end

  test "a value updates the source and every client" do
    {kino, _source} = start_smart_cell!(ConfigCell, %{})
    push_event(kino, "set", %{"engine" => "fake_engine", "key" => "url", "value" => "https://h"})

    assert_smart_cell_update(
      kino,
      %{"values" => %{"fake_engine" => %{"url" => "https://h"}}},
      source
    )

    assert source =~ ~s|Loge.configure!(KinoLoge.Fake.Engine, url: "https://h")|
    assert_broadcast_event(kino, "values", %{"fake_engine" => %{"url" => "https://h"}})
  end

  test "verify probes the engine with the current values" do
    {kino, _source} =
      start_smart_cell!(ConfigCell, %{"values" => %{"fake_engine" => %{"url" => "https://h"}}})

    push_event(kino, "verify", %{"engine" => "fake_engine"})

    assert_broadcast_event(
      kino,
      "verified",
      %{engine: "fake_engine", ok: true, message: nil},
      1_000
    )

    push_event(kino, "set", %{"engine" => "fake_engine", "key" => "url", "value" => "ftp://h"})
    push_event(kino, "verify", %{"engine" => "fake_engine"})

    assert_broadcast_event(
      kino,
      "verified",
      %{engine: "fake_engine", ok: false, message: ~s|{:bad_url, "ftp://h"}|},
      1_000
    )
  end

  test "unknown events and engines change nothing" do
    {kino, _source} = start_smart_cell!(ConfigCell, %{})
    push_event(kino, "verify", %{"engine" => "gone"})
    push_event(kino, "set", %{"engine" => "gone", "key" => "url", "value" => "x"})
    push_event(kino, "boom", nil)

    assert connect(kino).engines |> hd() |> Map.fetch!(:id) == "fake_engine"
    refute_received {:runtime_smart_cell_update, _, _, _, _}
  end
end
