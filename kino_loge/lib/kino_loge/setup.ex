defmodule KinoLoge.Setup do
  @moduledoc """
  What a Logic Engine cell is set to: its language, its engine and the engine's
  control values, the variable a definitions cell binds, and the source.

  An engine of `nil` makes a definitions cell, whose source another cell includes
  through `variable`. The setup round-trips through the cell's attrs, which a
  notebook stores as JSON: ids, keys and choices are matched by their string form, so
  nothing read from a notebook becomes an atom.
  """

  alias Loge.{Control, Registry}

  @enforce_keys [:language, :engine, :options, :variable, :source]
  defstruct @enforce_keys

  @typedoc "A cell's language and engine modules, control values in control order, variable and source."
  @type t :: %__MODULE__{
          language: module(),
          engine: module() | nil,
          options: keyword(),
          variable: String.t(),
          source: String.t()
        }

  @doc """
  The setup stored in `attrs`. A missing or unknown language is the first registered
  one, a missing or unknown engine the language's first, and a missing or invalid
  control value the control's default. An `"engine"` of `nil` is a definitions cell.
  Raises `ArgumentError` when no language is registered.
  """
  @spec from_attrs(map()) :: t()
  def from_attrs(attrs) when is_map(attrs) do
    language = find(Registry.languages(), attrs["language"]) || first_language()

    engine =
      case Map.fetch(attrs, "engine") do
        {:ok, nil} -> nil
        {:ok, id} -> find(engines(language), id) || first_engine(language)
        :error -> first_engine(language)
      end

    %__MODULE__{
      language: language,
      engine: engine,
      options: options(engine, Map.get(attrs, "options", %{})),
      variable: variable(attrs["variable"]),
      source: Map.get(attrs, "source", "")
    }
  end

  @doc "The attrs `from_attrs/1` reads back."
  @spec to_attrs(t()) :: map()
  def to_attrs(%__MODULE__{} = setup) do
    %{
      "language" => id(setup.language),
      "engine" => setup.engine && id(setup.engine),
      "options" => Map.new(setup.options, fn {key, value} -> {Atom.to_string(key), value} end),
      "variable" => setup.variable,
      "source" => setup.source
    }
  end

  @doc """
  The Elixir the cell evaluates: `Loge.Engine.to_source/4` for an engine cell,
  `Loge.Source.to_source/3` for a definitions cell.
  """
  @spec to_source(t()) :: String.t()
  def to_source(%__MODULE__{engine: nil} = setup) do
    Loge.Source.to_source(setup.language.id(), setup.source, setup.variable)
  end

  def to_source(%__MODULE__{} = setup) do
    options = Enum.reject(setup.options, fn {_key, value} -> is_nil(value) end)

    Loge.Engine.to_source(
      setup.engine,
      setup.source,
      options,
      setup.language.include_names(setup.source)
    )
  end

  @doc "The registered language with id `id`, with its first engine and that engine's defaults."
  @spec put_language(t(), String.t()) :: t()
  def put_language(%__MODULE__{} = setup, id) do
    case find(Registry.languages(), id) do
      nil -> setup
      language -> with_engine(%{setup | language: language}, first_engine(language))
    end
  end

  @doc "The language's engine with id `id`, with its defaults; `nil` makes a definitions cell."
  @spec put_engine(t(), String.t() | nil) :: t()
  def put_engine(%__MODULE__{} = setup, nil), do: with_engine(setup, nil)

  def put_engine(%__MODULE__{} = setup, id) do
    case find(engines(setup.language), id) do
      nil -> setup
      engine -> with_engine(setup, engine)
    end
  end

  @doc "Sets the control whose key is `key` to `value`, if the value suits the control."
  @spec put_option(t(), String.t(), term()) :: t()
  def put_option(%__MODULE__{engine: nil} = setup, _key, _value), do: setup

  def put_option(%__MODULE__{} = setup, key, value) do
    with %Control{} = control <-
           Enum.find(setup.engine.controls(), &(Atom.to_string(&1.key) == key)),
         {:ok, value} <- cast(control, value) do
      %{setup | options: Keyword.replace!(setup.options, control.key, value)}
    else
      _invalid -> setup
    end
  end

  @doc "Binds a definitions cell to `name`, a variable name or `\"\"`."
  @spec put_variable(t(), String.t()) :: t()
  def put_variable(%__MODULE__{} = setup, name) do
    case variable(name) do
      ^name -> %{setup | variable: name}
      _invalid -> setup
    end
  end

  @doc "Replaces the source."
  @spec put_source(t(), String.t()) :: t()
  def put_source(%__MODULE__{} = setup, source) when is_binary(source),
    do: %{setup | source: source}

  @doc "The choices of a control, with dynamic ones resolved."
  @spec choices(Control.t()) :: [term()]
  def choices(%Control{choices: {:dynamic, choices}}), do: choices.()
  def choices(%Control{choices: choices}), do: choices

  defp with_engine(setup, engine), do: %{setup | engine: engine, options: options(engine, %{})}

  defp options(nil, _stored), do: []

  defp options(engine, stored) when is_map(stored) do
    for control <- engine.controls() do
      case cast(control, Map.get(stored, Atom.to_string(control.key))) do
        {:ok, value} -> {control.key, value}
        :error -> {control.key, control.default}
      end
    end
  end

  defp options(engine, _stored), do: options(engine, %{})

  defp cast(%Control{type: :integer}, value) when is_integer(value), do: {:ok, value}

  defp cast(%Control{type: :integer}, value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> {:ok, integer}
      _other -> :error
    end
  end

  defp cast(%Control{type: :boolean}, value) when is_boolean(value), do: {:ok, value}
  defp cast(%Control{type: :text}, value) when is_binary(value), do: {:ok, value}

  defp cast(%Control{type: :select} = control, value) when not is_nil(value) do
    case Enum.find(choices(control), &(&1 == value or to_string(&1) == value)) do
      nil -> :error
      choice -> {:ok, choice}
    end
  end

  defp cast(%Control{}, _value), do: :error

  defp variable(name) when is_binary(name) do
    case Loge.Variable.parse(name) do
      {:ok, _variable} -> name
      :error -> ""
    end
  end

  defp variable(_name), do: ""

  defp engines(language), do: Registry.engines_for(language.id())

  defp first_engine(language), do: List.first(engines(language))

  defp first_language do
    case Registry.languages() do
      [language | _] -> language
      [] -> raise ArgumentError, "no Loge language is registered"
    end
  end

  defp find(modules, id) when is_binary(id), do: Enum.find(modules, &(id(&1) == id))
  defp find(_modules, _id), do: nil

  defp id(module), do: Atom.to_string(module.id())
end
