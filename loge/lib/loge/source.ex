defmodule Loge.Source do
  @moduledoc """
  Source text in a language, as a value one cell defines and another includes or runs.

  A notebook cell binds one to a variable; a later cell names the variable in an
  include and receives it under the `:includes` option of `c:Loge.Language.analyze/2`
  and `c:Loge.Engine.run/2`, or takes it as the input of a run.

  A source carries the sources its own includes name, so it can be included or run
  from anywhere without its includes being named again. `closure/2` collects them.

      set_theory = Loge.source(:tptp, "fof(extensionality, axiom, ...).")
      problem = Loge.source(:tptp, "include('set_theory'). ...", includes: %{"set_theory" => set_theory})
  """

  @enforce_keys [:language, :text]
  defstruct [:language, :text, includes: %{}]

  @typedoc "Text, the id of the language it is written in, and the sources it includes."
  @type t :: %__MODULE__{language: atom(), text: binary(), includes: Loge.Language.includes()}

  @typedoc """
  The names a generated `Loge.source/3` call refers to: `:includes`, the include names
  of the text, each passed as the variable of that name where it is one; `:bind`, the
  variable the source is bound to.
  """
  @type references :: [includes: [String.t()], bind: String.t()]

  @doc """
  The Elixir a notebook evaluates for a cell that defines a source: a `Loge.source/3`
  call, bound to the variable `:bind` names. Raises `ArgumentError` when that is not a
  variable name.

      iex> Loge.Source.to_source(:tptp, "fof(a, axiom, p).", bind: "defs")
      ~s|defs = Loge.source(:tptp, "fof(a, axiom, p).")|

      iex> Loge.Source.to_source(:tptp, "include('defs').", bind: "problem", includes: ["defs"])
      ~s|problem = Loge.source(:tptp, "include('defs').", includes: %{"defs" => defs})|
  """
  @spec to_source(atom(), binary(), references()) :: binary()
  def to_source(language, text, references) when is_atom(language) and is_binary(text) do
    references = Keyword.validate!(references, [:bind, includes: []])

    arguments =
      case Loge.Variable.includes(references[:includes]) do
        [] -> [language, text]
        includes -> [language, text, includes]
      end

    quote(do: Loge.source(unquote_splicing(arguments)))
    |> Loge.Variable.bind(references[:bind])
    |> Macro.to_string()
  end

  @doc """
  Every source `input` and `includes` reach, by the name an include uses: those in
  `includes`, then those `input` carries, then the ones each of those carries, and so
  on. A name keeps the first source found for it, so a name given to a run shadows the
  same name inside a source it includes. An outcome carries what its output carries.
  """
  @spec closure(Loge.Input.t(), Loge.Language.includes()) :: Loge.Language.includes()
  def closure(input, includes) when is_map(includes), do: reach([includes, carried(input)], %{})

  defp reach([], found), do: found

  defp reach([includes | rest], found) do
    new = Map.drop(includes, Map.keys(found))
    reach(rest ++ Enum.map(Map.values(new), &carried/1), Map.merge(found, new))
  end

  defp carried(%__MODULE__{includes: includes}), do: includes
  defp carried(%Loge.Outcome{output: %__MODULE__{} = output}), do: carried(output)
  defp carried(_input), do: %{}
end

defimpl Loge.Input, for: Loge.Source do
  def to_iodata(%Loge.Source{text: text}), do: text
  def language(%Loge.Source{language: language}), do: language
end
