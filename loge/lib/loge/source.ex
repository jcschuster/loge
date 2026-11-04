defmodule Loge.Source do
  @moduledoc """
  Source text in a language, as a value one cell defines and another includes.

  A notebook cell binds one to a variable; a later cell of the same language names
  the variable in an include and receives it under the `:includes` option of
  `c:Loge.Language.analyze/2` and `c:Loge.Engine.run/2`.

      set_theory = Loge.source(:tptp, "fof(extensionality, axiom, ...).")
  """

  @enforce_keys [:language, :text]
  defstruct [:language, :text]

  @typedoc "Text and the id of the language it is written in."
  @type t :: %__MODULE__{language: atom(), text: binary()}

  @doc """
  The Elixir a notebook evaluates for a cell that defines a source: a
  `Loge.source/2` call, bound to `variable` unless it is empty. Raises
  `ArgumentError` when `variable` is not a variable name.

      iex> Loge.Source.to_source(:tptp, "fof(a, axiom, p).", "defs")
      ~s|defs = Loge.source(:tptp, "fof(a, axiom, p).")|
  """
  @spec to_source(atom(), binary(), String.t()) :: binary()
  def to_source(language, text, variable) when is_atom(language) and is_binary(text) do
    call = quote(do: Loge.source(unquote(language), unquote(text)))
    variable |> bind(call) |> Macro.to_string()
  end

  defp bind("", call), do: call

  defp bind(variable, call) do
    case Loge.Variable.parse(variable) do
      {:ok, name} -> quote(do: unquote(Macro.var(name, nil)) = unquote(call))
      :error -> raise ArgumentError, "not a variable name: #{inspect(variable)}"
    end
  end
end

defimpl Loge.Input, for: Loge.Source do
  def to_iodata(%Loge.Source{text: text}), do: text
  def language(%Loge.Source{language: language}), do: language
end
