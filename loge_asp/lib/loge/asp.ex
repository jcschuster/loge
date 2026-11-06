defmodule Loge.Asp do
  @moduledoc """
  Answer Set Programming for Loge: clingo's input language and clingo as its engine.

  | Module | Over |
  |--------|------|
  | `Loge.Asp.Language` | `clingo --solve-limit=0` |
  | `Loge.Asp.Engines.Clingo` | `clingo --outf=2` |

  Both run the `clingo` executable bundled with `clingo_elixir` and are registered
  with `Loge` when `:loge_asp` starts.
  """

  @doc "The modules `:loge_asp` registers with `Loge`."
  @spec modules() :: [module()]
  def modules, do: [Loge.Asp.Language, Loge.Asp.Engines.Clingo]
end
