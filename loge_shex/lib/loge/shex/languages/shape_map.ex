defmodule Loge.Shex.Languages.ShapeMap do
  @time_limit 10

  @moduledoc """
  ShEx shape maps in rudof's compact syntax as a `Loge.Language`: pairs `node@shape`,
  separated by commas, which say which nodes of the data are validated against which
  shapes of the schema.

  A shape map declares no prefixes: its nodes are read with the data's and its shapes
  with the schema's. Its analysis therefore takes the `:roles` of
  `Loge.Shex.Engines.Validate`, `:schema` and `:data` (`t:Loge.Language.roles/0`).
  With both, it is read as a validation reads it; when one of them does not read, the
  shape map is left unchecked, and the cell that holds the role shows why. Without
  both, only its syntax is checked. Positions are as `Loge.Shex.Messages` reads them.

  Reading the schema fetches what it imports, so the analysis runs in a `Loge.Peer`
  and is stopped after #{@time_limit} seconds, then holding no diagnostic. The analysis
  has no `native`.
  """

  @behaviour Loge.Language

  alias Loge.Shex.{Messages, Runner}

  @impl true
  def id, do: :shapemap

  @impl true
  def label, do: "ShapeMap"

  @impl true
  def extensions, do: [".sm"]

  @impl true
  def editor_language, do: "shapemap"

  @impl true
  def include_names(source) when is_binary(source), do: []

  @impl true
  def analyze(source, options) when is_binary(source) do
    roles = Keyword.get(options, :roles, [])

    diagnostics =
      case {roles[:data], roles[:schema]} do
        {nil, _schema} -> syntax(source)
        {_data, nil} -> syntax(source)
        {data, schema} -> read(source, text(data), text(schema))
      end

    %Loge.Analysis{language: :shapemap, source: source, diagnostics: diagnostics, native: nil}
  end

  defp syntax(source), do: source |> read("", "") |> Enum.filter(&(&1.code == "syntax_error"))

  defp read(source, data, schema) do
    case Loge.Peer.call(Runner, :read_shapemap, [source, data, schema],
           timeout: @time_limit * 1000
         ) do
      {:ok, :ok} -> []
      {:ok, {:error, {:invalid_shapemap, message}}} -> [Messages.diagnostic(message, source)]
      {:ok, {:error, _role_or_rudof}} -> []
      {:error, :timeout} -> []
    end
  end

  defp text(input), do: input |> Loge.Input.to_iodata() |> IO.iodata_to_binary()
end
