defmodule Loge.Turtle.Runner do
  @moduledoc """
  The part of `Loge.Turtle.Engines.Shacl` that runs in a `Loge.Peer`: rudof's native
  code cannot be interrupted, so a run is cancelled, or stopped at its time limit, by
  ending the peer it runs in.
  """

  alias Rudof.Session

  @typedoc "What a validation gives: the report as rudof's map and as Turtle."
  @type report :: %{conforms: boolean(), results: [map()], turtle: String.t()}

  @doc """
  Validates the Turtle `data` against the SHACL `shapes`, also Turtle. An input that
  does not read is `{:error, {:invalid_shapes | :invalid_data, message}}`; any other
  failure is `{:error, {:rudof, message}}`.
  """
  @spec validate(binary(), binary()) :: {:ok, report()} | {:error, {atom(), String.t()}}
  def validate(data, shapes) when is_binary(data) and is_binary(shapes) do
    Session.with_session(fn session ->
      with :ok <- read(:invalid_shapes, Session.read_shacl(session, shapes, format: :turtle)),
           :ok <- read(:invalid_data, Session.read_data(session, data, format: :turtle)),
           {:ok, report} <- rudof(Session.validate_shacl(session)),
           {:ok, turtle} <- rudof(Session.serialize_shacl_validation_results(session, :turtle)) do
        {:ok, Map.put(report, :turtle, turtle)}
      end
    end)
  end

  defp read(_reason, :ok), do: :ok
  defp read(reason, {:error, %Rudof.Error{message: message}}), do: {:error, {reason, message}}

  defp rudof({:ok, value}), do: {:ok, value}
  defp rudof({:error, %Rudof.Error{message: message}}), do: {:error, {:rudof, message}}
end
