defmodule Loge.Shex do
  @moduledoc """
  ShEx for Loge, over rudof (`rudof_elixir`): schemas in ShExC, the shape maps that
  say which nodes are validated against which shapes, and validation.

  | Module | Over |
  |--------|------|
  | `Loge.Shex.Languages.Shexc` | `Rudof.Session.check_shex/3`, in a `Loge.Peer` |
  | `Loge.Shex.Languages.ShapeMap` | `Rudof.Session.read_shapemap/3`, in a `Loge.Peer` |
  | `Loge.Shex.Engines.Validate` | `Rudof.Session.validate_shex/1`, in a `Loge.Peer` |

  A shape map is the input of a validation, and the schema and the data are its roles
  (`Loge.Role`): one schema is asked many shape maps, as one program is asked many
  queries. All three modules are registered with `Loge` when `:loge_shex` starts.
  """

  @doc "The modules `:loge_shex` registers with `Loge`."
  @spec modules() :: [module()]
  def modules,
    do: [Loge.Shex.Languages.Shexc, Loge.Shex.Languages.ShapeMap, Loge.Shex.Engines.Validate]
end
