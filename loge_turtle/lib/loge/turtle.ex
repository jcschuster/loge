defmodule Loge.Turtle do
  @moduledoc """
  RDF in Turtle for Loge, over rudof (`rudof_elixir`): the language and SHACL
  validation.

  | Module | Over |
  |--------|------|
  | `Loge.Turtle.Language` | `Rudof.Session.read_data/3` |
  | `Loge.Turtle.Engines.Shacl` | `Rudof.Session.validate_shacl/2`, in a `Loge.Peer` |

  Both are registered with `Loge` when `:loge_turtle` starts.
  """

  @doc "The modules `:loge_turtle` registers with `Loge`."
  @spec modules() :: [module()]
  def modules, do: [Loge.Turtle.Language, Loge.Turtle.Engines.Shacl]
end
