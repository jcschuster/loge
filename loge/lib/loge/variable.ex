defmodule Loge.Variable do
  @moduledoc """
  Elixir variable names as they appear in generated cell source.

  A notebook passes sources and outcomes between cells through variables, and an
  include names a source by its variable, so an include name is either a variable name
  or a name the language resolves on its own, such as a library path.

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

  @doc """
  The quoted `:includes` option for include names: each name that is a variable name,
  once, passed as that variable. Empty when none is.

      iex> Loge.Variable.includes(["defs", "Axioms/SET001+0.ax"]) |> Macro.to_string()
      ~s|[includes: %{"defs" => defs}]|
  """
  @spec includes([String.t()]) :: keyword(Macro.t())
  def includes(names) when is_list(names) do
    case for {:ok, variable} <- names |> Enum.uniq() |> Enum.map(&parse/1),
             do: {Atom.to_string(variable), Macro.var(variable, nil)} do
      [] -> []
      pairs -> [includes: {:%{}, [], pairs}]
    end
  end

  @doc """
  The quoted expression bound to the variable `name`, or the expression itself when
  `name` is `nil`. Raises `ArgumentError` when `name` is not a variable name.

      iex> Loge.Variable.bind(quote(do: f()), "result") |> Macro.to_string()
      "result = f()"
  """
  @spec bind(Macro.t(), String.t() | nil) :: Macro.t()
  def bind(expression, nil), do: expression

  def bind(expression, name) when is_binary(name) do
    case parse(name) do
      {:ok, variable} -> quote(do: unquote(Macro.var(variable, nil)) = unquote(expression))
      :error -> raise ArgumentError, "not a variable name: #{inspect(name)}"
    end
  end
end
