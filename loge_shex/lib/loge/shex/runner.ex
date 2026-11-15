defmodule Loge.Shex.Runner do
  @moduledoc """
  The part of `loge_shex` that runs in a `Loge.Peer`. Reading a ShExC schema fetches
  what it imports, without a time limit, and rudof's native code cannot be
  interrupted, so a lint or a validation is stopped at its deadline, or cancelled, by
  ending the peer it runs in.
  """

  alias Rudof.Session

  @typedoc "Why an input has no result: what does not read, in rudof's words, or rudof's failure."
  @type failure ::
          {:invalid_shapemap | :invalid_schema | :invalid_data | :rudof, String.t()}

  @doc "Checks a ShExC schema: whether it is valid, and rudof's account of it."
  @spec check(binary()) :: {:ok, {boolean(), String.t()}} | {:error, failure()}
  def check(schema) when is_binary(schema) do
    Session.with_session(&read(:rudof, Session.check_shex(&1, schema)))
  end

  @doc "Reads a shape map with the prefixes of the Turtle `data` and the ShExC `schema`."
  @spec read_shapemap(binary(), binary(), binary()) :: :ok | {:error, failure()}
  def read_shapemap(shapemap, data, schema) do
    Session.with_session(&load(&1, shapemap, data, schema))
  end

  @doc """
  Validates the Turtle `data` against the ShExC `schema` as the `shapemap` says.
  Returns rudof's result and its compact serialisation, a table of the pairs.
  """
  @spec validate(binary(), binary(), binary()) :: {:ok, {map(), String.t()}} | {:error, failure()}
  def validate(shapemap, data, schema) do
    Session.with_session(fn session ->
      with :ok <- load(session, shapemap, data, schema),
           {:ok, result} <- read(:rudof, Session.validate_shex(session)),
           {:ok, raw} <-
             read(:rudof, Session.serialize_shex_validation_results(session, :compact)),
           do: {:ok, {result, raw}}
    end)
  end

  defp load(session, shapemap, data, schema) do
    with :ok <- read(:invalid_schema, Session.read_shex(session, schema, format: :shexc)),
         :ok <- read(:invalid_data, Session.read_data(session, data, format: :turtle)),
         do: read(:invalid_shapemap, Session.read_shapemap(session, shapemap, format: :compact))
  end

  defp read(_reason, :ok), do: :ok
  defp read(_reason, {:ok, value}), do: {:ok, value}
  defp read(reason, {:error, %Rudof.Error{message: message}}), do: {:error, {reason, message}}
end
