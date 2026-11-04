defmodule Loge.Tptp.Includes do
  @moduledoc """
  How an `include` in a TPTP source is resolved: first against the
  `t:Loge.Language.includes/0` by the exact name written, then against the TPTP
  library through `library`, a `Tptp.Resolver` that defaults to `Tptp.Resolver.Http`.
  """

  @typedoc "Where names the includes do not hold are read from."
  @type library :: Tptp.Resolver.t()

  @doc "The `Tptp.Resolver` for a source with these includes."
  @spec resolver(Loge.Language.includes(), library()) :: Tptp.Resolver.t()
  def resolver(includes, library) do
    files = Map.new(includes, fn {name, input} -> {name, text(input)} end)
    {Tptp.Resolver.Cascade, resolvers: [{Tptp.Resolver.Map, files: files}, library]}
  end

  @doc """
  What a prover reads for `input`: the input itself without includes, since a
  prover resolves library includes on its own, or a `Tptp.Unit` with every include
  inlined. An include that cannot be resolved is
  `{:error, {:unresolved_includes, diagnostics}}`.
  """
  @spec input(Loge.Input.t(), Loge.Language.includes(), library()) ::
          {:ok, Loge.Input.t()} | {:error, {:unresolved_includes, [Tptp.Diagnostic.t()]}}
  def input(input, includes, _library) when map_size(includes) == 0, do: {:ok, input}

  def input(input, includes, library) do
    {:ok, unit, diagnostics} =
      Tptp.Unit.from_string(text(input), resolver: resolver(includes, library))

    case Enum.filter(diagnostics, &unresolved?/1) do
      [] -> {:ok, unit}
      unresolved -> {:error, {:unresolved_includes, unresolved}}
    end
  end

  defp text(input), do: input |> Loge.Input.to_iodata() |> IO.iodata_to_binary()

  defp unresolved?(%Tptp.Diagnostic{code: "TPTP06" <> _, severity: :error}), do: true
  defp unresolved?(%Tptp.Diagnostic{}), do: false
end
