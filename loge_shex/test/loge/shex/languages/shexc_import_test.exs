defmodule Loge.Shex.Languages.ShexcImportTest do
  use ExUnit.Case, async: false

  alias Loge.Shex.Languages.Shexc

  test "an import from a server that never answers is cut off after ten seconds" do
    {:ok, listen} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(listen)

    spawn_link(fn ->
      {:ok, _socket} = :gen_tcp.accept(listen)
      Process.sleep(:infinity)
    end)

    schema = "IMPORT <http://127.0.0.1:#{port}/defs.shex>\n<http://e/S> { <http://e/p> . }\n"

    {microseconds, analysis} = :timer.tc(fn -> Shexc.analyze(schema, []) end)

    assert analysis.diagnostics == []
    assert microseconds in 10_000_000..12_000_000
  end
end
