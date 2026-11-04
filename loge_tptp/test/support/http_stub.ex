defmodule Loge.Tptp.HttpStub do
  @moduledoc false

  @spec start(binary()) :: String.t()
  def start(body) do
    {:ok, listen} = :gen_tcp.listen(0, [:binary, active: false, packet: :raw, reuseaddr: true])
    {:ok, port} = :inet.port(listen)
    pid = spawn_link(fn -> serve(listen, body) end)
    :ok = :gen_tcp.controlling_process(listen, pid)
    "http://127.0.0.1:#{port}/form"
  end

  defp serve(listen, body) do
    {:ok, socket} = :gen_tcp.accept(listen)
    read_request(socket, "")

    :ok =
      :gen_tcp.send(socket, [
        "HTTP/1.1 200 OK\r\ncontent-type: text/plain\r\nconnection: close\r\n",
        "content-length: #{byte_size(body)}\r\n\r\n",
        body
      ])

    :gen_tcp.close(socket)
    serve(listen, body)
  end

  defp read_request(socket, received) do
    case :binary.split(received, "\r\n\r\n") do
      [head, rest] -> read_body(socket, rest, content_length(head))
      [_partial] -> read_request(socket, received <> recv(socket))
    end
  end

  defp read_body(_socket, body, length) when byte_size(body) >= length, do: body
  defp read_body(socket, body, length), do: read_body(socket, body <> recv(socket), length)

  defp recv(socket) do
    {:ok, data} = :gen_tcp.recv(socket, 0, 5_000)
    data
  end

  defp content_length(head) do
    case Regex.run(~r/content-length:\s*(\d+)/i, head) do
      [_, length] -> String.to_integer(length)
      nil -> 0
    end
  end
end
