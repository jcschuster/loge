defmodule KinoLoge.SourceSetup do
  @moduledoc """
  What a Logic Source cell is set to: its language, the variable it binds and its
  source. Every registered language is offered, whether or not an engine reads it.

  The setup round-trips through the cell's attrs as `KinoLoge.Setup` does: the language
  is matched by its id's string form and the variable becomes one only through
  `Loge.Variable.parse/1`.
  """

  alias Loge.Registry

  @enforce_keys [:language, :variable, :source]
  defstruct @enforce_keys

  @typedoc "A cell's language module, the variable it binds and its source."
  @type t :: %__MODULE__{language: module(), variable: String.t(), source: String.t()}

  @doc """
  The setup stored in `attrs`. A missing or unknown language is the first registered
  one, and a missing or invalid variable `source`. Raises `ArgumentError` when no
  language is registered.
  """
  @spec from_attrs(map()) :: t()
  def from_attrs(attrs) when is_map(attrs) do
    %__MODULE__{
      language: language(attrs["language"]) || first_language(),
      variable: variable(attrs["variable"]) || "source",
      source: Map.get(attrs, "source", "")
    }
  end

  @doc "The attrs `from_attrs/1` reads back."
  @spec to_attrs(t()) :: map()
  def to_attrs(%__MODULE__{} = setup) do
    %{
      "language" => Atom.to_string(setup.language.id()),
      "variable" => setup.variable,
      "source" => setup.source
    }
  end

  @doc """
  The Elixir the cell evaluates, `Loge.Source.to_source/3`: the source bound to the
  variable, with the includes it names.
  """
  @spec to_source(t()) :: String.t()
  def to_source(%__MODULE__{} = setup) do
    Loge.Source.to_source(setup.language.id(), setup.source,
      bind: setup.variable,
      includes: setup.language.include_names(setup.source)
    )
  end

  @doc "The registered language with id `id`."
  @spec put_language(t(), String.t()) :: t()
  def put_language(%__MODULE__{} = setup, id) do
    case language(id) do
      nil -> setup
      language -> %{setup | language: language}
    end
  end

  @doc "Binds the source to `name`, if it is a variable name."
  @spec put_variable(t(), String.t()) :: t()
  def put_variable(%__MODULE__{} = setup, name) do
    case variable(name) do
      nil -> setup
      name -> %{setup | variable: name}
    end
  end

  @doc "Replaces the source."
  @spec put_source(t(), String.t()) :: t()
  def put_source(%__MODULE__{} = setup, source) when is_binary(source),
    do: %{setup | source: source}

  defp language(id) when is_binary(id) do
    case Registry.language(id) do
      {:ok, language} -> language
      :error -> nil
    end
  end

  defp language(_id), do: nil

  defp variable(name) when is_binary(name) do
    case Loge.Variable.parse(name) do
      {:ok, _variable} -> name
      :error -> nil
    end
  end

  defp variable(_name), do: nil

  defp first_language do
    case Registry.languages() do
      [language | _] -> language
      [] -> raise ArgumentError, "no Loge language is registered"
    end
  end
end
