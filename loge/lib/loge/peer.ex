defmodule Loge.Peer do
  @moduledoc """
  Calls a function in a fresh BEAM, an OS process of its own that stops when the
  caller dies.

  Native code a NIF runs on a dirty scheduler cannot be interrupted from Elixir; it
  holds its scheduler until it returns, even after the caller died. In a peer it ends
  with the peer, which a `Loge.Guard` stops when the caller dies. This is how an
  engine over such a NIF honours the cancellation contract of `Loge.Engine`.

  The peer has this node's code path but none of its state: no application is started,
  and arguments and results are copied, so references to NIF resources cannot cross.
  Starting one takes about a tenth of a second.
  """

  @doc """
  Applies `function` of `module` to `args` in a fresh peer and returns the result;
  an exception the call raises is raised in the caller. The peer stops afterwards.

      Loge.Peer.call(System, :pid, [])
  """
  @spec call(module(), atom(), [term()]) :: term()
  def call(module, function, args) when is_atom(module) and is_atom(function) and is_list(args) do
    code_path = Enum.flat_map(:code.get_path(), &[~c"-pa", &1])
    {:ok, peer, _node} = :peer.start(%{connection: :standard_io, args: code_path})
    guard = Loge.Guard.start(fn -> :peer.stop(peer) end)

    try do
      :peer.call(peer, module, function, args, :infinity)
    after
      Loge.Guard.dismiss(guard)
      :peer.stop(peer)
    end
  end
end
