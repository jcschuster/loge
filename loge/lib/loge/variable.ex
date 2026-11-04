defmodule Loge.Variable do
  @moduledoc """
  Elixir variable names as they appear in generated cell source.

  A notebook passes sources between cells through variables, and an include names a
  source by its variable, so an include name is either a variable name or a name the
  language resolves on its own, such as a library path.

  Parsing a name creates its atom, as evaluating the generated source would. Only a
  name that parses as a lone variable is accepted.
  """

  @doc """
  The atom of a variable name, or `:error` when the name is not one.

      iex> Loge.Variable.parse("set_theory")
      {:ok, :set_theory}

      iex> Loge.Variable.parse("Axioms/SET001+0.ax")
      :error
  """
  @spec parse(String.t()) :: {:ok, atom()} | :error
  def parse(name) when is_binary(name) do
    case Code.string_to_quoted(name) do
      {:ok, {variable, _meta, nil}} when is_atom(variable) -> {:ok, variable}
      _other -> :error
    end
  end
end
