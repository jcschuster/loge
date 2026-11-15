defmodule KinoLoge.Setup do
  @moduledoc """
  What a Logic Engine cell is set to: its language, its engine and the engine's
  control values, its input, the variable that holds each of the engine's roles, the
  variable its outcome is bound to, and the source in its editor.

  The input is the source in the editor (`nil`) or the name of a variable that holds a
  bound input, a source or an outcome with an output. A role (`Loge.Role`) is unset
  (`nil`) or the name of such a variable; an engine's roles start unset. The setup round-trips through the
  cell's attrs, which a notebook stores as JSON: ids, keys and choices are matched by
  their string form, so nothing read from a notebook becomes an atom, and names become
  variables only through `Loge.Variable.parse/1`.
  """

  alias Loge.{Control, Registry}

  @enforce_keys [:language, :engine, :options, :input, :roles, :variable, :source]
  defstruct @enforce_keys

  @typedoc """
  A cell's language and engine modules, control values in control order, input
  variable (`nil` for the editor), role variables in role order (`nil` for unset),
  result variable (`""` for none) and source.
  """
  @type t :: %__MODULE__{
          language: module(),
          engine: module(),
          options: keyword(),
          input: String.t() | nil,
          roles: [{atom(), String.t() | nil}],
          variable: String.t(),
          source: String.t()
        }

  @doc "The languages a Logic Engine cell offers: those with a registered engine."
  @spec languages() :: [module()]
  def languages, do: Enum.filter(Registry.languages(), &(engines(&1) != []))

  @doc """
  The setup stored in `attrs`. A missing or unknown language is the first one
  `languages/0` offers, a missing or unknown engine the language's first, a missing or
  invalid control value the control's default, and a missing or invalid name the
  editor as input, an unset role and no result variable. Raises `ArgumentError` when no language has
  an engine.
  """
  @spec from_attrs(map()) :: t()
  def from_attrs(attrs) when is_map(attrs) do
    language = language(attrs["language"]) || first_language()
    engine = engine(language, attrs["engine"]) || first_engine(language)

    %__MODULE__{
      language: language,
      engine: engine,
      options: options(engine, Map.get(attrs, "options", %{})),
      input: name(attrs["input"], nil),
      roles: roles(engine, Map.get(attrs, "roles", %{})),
      variable: name(attrs["variable"], ""),
      source: Map.get(attrs, "source", "")
    }
  end

  @doc "The attrs `from_attrs/1` reads back."
  @spec to_attrs(t()) :: map()
  def to_attrs(%__MODULE__{} = setup) do
    %{
      "language" => id(setup.language),
      "engine" => id(setup.engine),
      "options" => Map.new(setup.options, fn {key, value} -> {Atom.to_string(key), value} end),
      "input" => setup.input,
      "roles" => Map.new(setup.roles, fn {key, name} -> {Atom.to_string(key), name} end),
      "variable" => setup.variable,
      "source" => setup.source
    }
  end

  @doc """
  The Elixir the cell evaluates, `Loge.Engine.to_source/4`: the engine run on the
  editor's source with the includes it names, or on the bound input, which carries its
  own includes; each set role passed its variable; bound to the result variable when
  there is one.
  """
  @spec to_source(t()) :: String.t()
  def to_source(%__MODULE__{} = setup) do
    options = Enum.reject(setup.options, fn {_key, value} -> is_nil(value) end)
    roles = Enum.reject(setup.roles, fn {_key, name} -> is_nil(name) end)
    {input, includes} = input(setup)
    references = [roles: roles, includes: includes] ++ bind(setup)

    Loge.Engine.to_source(setup.engine, input, options, references)
  end

  @doc """
  The language with id `id` among `languages/0`, with its first engine, that engine's
  defaults and the editor as input.
  """
  @spec put_language(t(), String.t()) :: t()
  def put_language(%__MODULE__{} = setup, id) do
    case language(id) do
      nil -> setup
      language -> with_engine(%{setup | language: language, input: nil}, first_engine(language))
    end
  end

  @doc "The language's engine with id `id`, with its defaults and its roles unset."
  @spec put_engine(t(), String.t()) :: t()
  def put_engine(%__MODULE__{} = setup, id) do
    case engine(setup.language, id) do
      nil -> setup
      engine -> with_engine(setup, engine)
    end
  end

  @doc """
  Sets the control whose key is `key` to `value`, if `Loge.Control.cast/2` reads it as
  the control's value.
  """
  @spec put_option(t(), String.t(), term()) :: t()
  def put_option(%__MODULE__{} = setup, key, value) do
    with %Control{} = control <-
           Enum.find(setup.engine.controls(), &(Atom.to_string(&1.key) == key)),
         {:ok, value} <- Control.cast(control, value) do
      %{setup | options: Keyword.replace!(setup.options, control.key, value)}
    else
      _invalid -> setup
    end
  end

  @doc "Takes the input from the editor (`nil`) or from the variable `name`."
  @spec put_input(t(), String.t() | nil) :: t()
  def put_input(%__MODULE__{} = setup, nil), do: %{setup | input: nil}

  def put_input(%__MODULE__{} = setup, name) do
    case name(name, nil) do
      nil -> setup
      name -> %{setup | input: name}
    end
  end

  @doc """
  Sets the role whose key is `key` to the variable `name`, or unsets it for `nil`. A
  key the engine has no role for, or a name that is no variable name, changes nothing.
  """
  @spec put_role(t(), String.t(), String.t() | nil) :: t()
  def put_role(%__MODULE__{} = setup, key, name) do
    with %Loge.Role{key: role} <-
           Enum.find(setup.engine.roles(), &(Atom.to_string(&1.key) == key)),
         {:ok, name} <- role_name(name) do
      %{setup | roles: Keyword.replace!(setup.roles, role, name)}
    else
      _invalid -> setup
    end
  end

  @doc "Binds the outcome to `name`, a variable name, or to nothing for `\"\"`."
  @spec put_variable(t(), String.t()) :: t()
  def put_variable(%__MODULE__{} = setup, ""), do: %{setup | variable: ""}

  def put_variable(%__MODULE__{} = setup, name) do
    case name(name, nil) do
      nil -> setup
      name -> %{setup | variable: name}
    end
  end

  @doc "Replaces the source in the editor."
  @spec put_source(t(), String.t()) :: t()
  def put_source(%__MODULE__{} = setup, source) when is_binary(source),
    do: %{setup | source: source}

  defp input(%__MODULE__{input: nil} = setup),
    do: {setup.source, setup.language.include_names(setup.source)}

  defp input(%__MODULE__{input: name}) do
    {:ok, variable} = Loge.Variable.parse(name)
    {variable, []}
  end

  defp bind(%__MODULE__{variable: ""}), do: []
  defp bind(%__MODULE__{variable: variable}), do: [bind: variable]

  defp with_engine(setup, engine),
    do: %{setup | engine: engine, options: options(engine, %{}), roles: roles(engine, %{})}

  defp options(engine, stored) when is_map(stored) do
    for control <- engine.controls() do
      case Control.cast(control, Map.get(stored, Atom.to_string(control.key))) do
        {:ok, value} -> {control.key, value}
        :error -> {control.key, control.default}
      end
    end
  end

  defp options(engine, _stored), do: options(engine, %{})

  defp roles(engine, stored) when is_map(stored),
    do: for(role <- engine.roles(), do: {role.key, name(stored[Atom.to_string(role.key)], nil)})

  defp roles(engine, _stored), do: roles(engine, %{})

  defp role_name(nil), do: {:ok, nil}

  defp role_name(name) do
    case name(name, nil) do
      nil -> :error
      name -> {:ok, name}
    end
  end

  defp name(name, none) when is_binary(name) do
    case Loge.Variable.parse(name) do
      {:ok, _variable} -> name
      :error -> none
    end
  end

  defp name(_name, none), do: none

  defp engines(language), do: Registry.engines_for(language.id())

  defp first_engine(language), do: hd(engines(language))

  defp first_language do
    case languages() do
      [language | _] -> language
      [] -> raise ArgumentError, "no Loge engine is registered"
    end
  end

  defp language(id) when is_binary(id), do: among(languages(), Registry.language(id))
  defp language(_id), do: nil

  defp engine(language, id) when is_binary(id),
    do: among(engines(language), Registry.engine(id))

  defp engine(_language, _id), do: nil

  defp among(modules, {:ok, module}), do: if(module in modules, do: module)
  defp among(_modules, :error), do: nil

  defp id(module), do: Atom.to_string(module.id())
end
