defmodule Loge.Registry do
  @moduledoc """
  The languages, analyzers, engines and libraries known to this node.

  Modules arrive from the `:languages`, `:engines`, `:analyzers` and `:libraries` lists
  in the `:loge` application environment, read when `:loge` starts, and from
  `register/1`. A module is filed under each of the `Loge.Language`, `Loge.Analyzer`,
  `Loge.Engine` and `Loge.Library` behaviours it declares, and its id is unique among
  the modules of that kind. The registry lives in `:persistent_term`: lookups are cheap
  and registration, which happens once per package start, is not.

  `language/1`, `engine/1` and `library/1` find a module by its id given as an atom or
  as the atom's string form, so a consumer reading an id from a notebook, a form or a
  JSON request makes no atom of it.
  """

  @kinds %{
    Loge.Language => :languages,
    Loge.Analyzer => :analyzers,
    Loge.Engine => :engines,
    Loge.Library => :libraries
  }

  @typedoc "Why a module could not be registered."
  @type error ::
          {:not_loaded, module()}
          | {:not_a_loge_module, module()}
          | {:duplicate_id, atom(), module()}

  @typedoc """
  A translation between two languages: the engine, the language it reads, the
  language it writes, and the status it preserves.
  """
  @type translation :: %{
          engine: module(),
          from: atom(),
          to: atom(),
          preserves: Loge.Status.t()
        }

  @doc """
  Registers a module under the behaviours it implements. Registering it again changes
  nothing; registering another module with an id its kind already holds is
  `{:error, {:duplicate_id, id, holder}}`.
  """
  @spec register(module()) :: :ok | {:error, error()}
  def register(module) when is_atom(module) do
    with {:ok, kinds} <- kinds(module),
         :ok <- unique(modules(), kinds, module) do
      :persistent_term.put(__MODULE__, Enum.reduce(kinds, modules(), &file(&2, &1, module)))
    end
  end

  @doc "Registered languages, in registration order."
  @spec languages() :: [module()]
  def languages, do: modules().languages

  @doc "Registered engines, in registration order."
  @spec engines() :: [module()]
  def engines, do: modules().engines

  @doc "Registered analyzers, in registration order."
  @spec analyzers() :: [module()]
  def analyzers, do: modules().analyzers

  @doc "Registered libraries, in registration order."
  @spec libraries() :: [module()]
  def libraries, do: modules().libraries

  @doc "The registered language with the id `id`, an atom or its string form."
  @spec language(atom() | String.t()) :: {:ok, module()} | :error
  def language(id), do: find(languages(), id)

  @doc "The registered engine with the id `id`, an atom or its string form."
  @spec engine(atom() | String.t()) :: {:ok, module()} | :error
  def engine(id), do: find(engines(), id)

  @doc "The registered library with the id `id`, an atom or its string form."
  @spec library(atom() | String.t()) :: {:ok, module()} | :error
  def library(id), do: find(libraries(), id)

  @doc "Engines whose `c:Loge.Engine.languages/0` include `language`."
  @spec engines_for(atom()) :: [module()]
  def engines_for(language), do: Enum.filter(engines(), &(language in &1.languages()))

  @doc "Analyzers for `language`, including those for any language."
  @spec analyzers_for(atom()) :: [module()]
  def analyzers_for(language) do
    Enum.filter(analyzers(), &(&1.languages() == :any or language in &1.languages()))
  end

  @doc "Libraries whose `c:Loge.Library.language/0` is `language`."
  @spec libraries_for(atom()) :: [module()]
  def libraries_for(language), do: Enum.filter(libraries(), &(&1.language() == language))

  @doc """
  The edges of the graph whose nodes are the languages: one per translate engine and
  language it reads, in registration order.
  """
  @spec translations() :: [translation()]
  def translations do
    for engine <- engines(),
        {:translate, to, preserves} <- [engine.task()],
        from <- engine.languages(),
        do: %{engine: engine, from: from, to: to, preserves: preserves}
  end

  @doc "The language claiming a file extension, such as `\".p\"`."
  @spec language_for_extension(String.t()) :: {:ok, module()} | :error
  def language_for_extension(extension) do
    case Enum.find(languages(), &(extension in &1.extensions())) do
      nil -> :error
      language -> {:ok, language}
    end
  end

  defp modules do
    :persistent_term.get(__MODULE__, %{languages: [], analyzers: [], engines: [], libraries: []})
  end

  defp find(modules, id) when is_atom(id), do: modules |> Enum.find(&(&1.id() == id)) |> found()

  defp find(modules, id) when is_binary(id),
    do: modules |> Enum.find(&(Atom.to_string(&1.id()) == id)) |> found()

  defp found(nil), do: :error
  defp found(module), do: {:ok, module}

  defp unique(modules, kinds, module) do
    holders =
      for kind <- kinds,
          holder <- modules[kind],
          holder != module and holder.id() == module.id(),
          do: holder

    case holders do
      [] -> :ok
      [holder | _] -> {:error, {:duplicate_id, module.id(), holder}}
    end
  end

  defp file(modules, kind, module) do
    Map.update!(modules, kind, &if(module in &1, do: &1, else: &1 ++ [module]))
  end

  defp kinds(module) do
    if Code.ensure_loaded?(module) do
      module.module_info(:attributes)
      |> Keyword.get_values(:behaviour)
      |> List.flatten()
      |> Enum.flat_map(&List.wrap(@kinds[&1]))
      |> loge_kinds(module)
    else
      {:error, {:not_loaded, module}}
    end
  end

  defp loge_kinds([], module), do: {:error, {:not_a_loge_module, module}}
  defp loge_kinds(kinds, _module), do: {:ok, kinds}
end
