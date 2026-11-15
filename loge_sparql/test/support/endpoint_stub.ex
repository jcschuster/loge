defmodule Loge.Sparql.EndpointStub do
  @moduledoc false

  @doc """
  Starts a SPARQL endpoint on localhost that answers every request with `body` and
  sends the request line to the calling process as `{:request, line}`.
  """
  @spec start(binary()) :: String.t()
  def start(body) do
    owner = self()
    {:ok, listen} = :gen_tcp.listen(0, [:binary, active: false, packet: :raw, reuseaddr: true])
    {:ok, port} = :inet.port(listen)
    pid = spawn_link(fn -> serve(listen, body, owner) end)
    :ok = :gen_tcp.controlling_process(listen, pid)
    "http://127.0.0.1:#{port}/sparql"
  end

  defp serve(listen, body, owner) do
    {:ok, socket} = :gen_tcp.accept(listen)
    {:ok, request} = :gen_tcp.recv(socket, 0, 5_000)
    send(owner, {:request, request |> String.split("\r\n") |> hd()})

    :ok =
      :gen_tcp.send(socket, [
        "HTTP/1.1 200 OK\r\ncontent-type: application/sparql-results+json\r\n",
        "connection: close\r\ncontent-length: #{byte_size(body)}\r\n\r\n",
        body
      ])

    :gen_tcp.close(socket)
    serve(listen, body, owner)
  end
end
