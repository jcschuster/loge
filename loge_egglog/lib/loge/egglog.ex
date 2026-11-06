defmodule Loge.Egglog do
  @moduledoc """
  egglog for Loge: the language over `Egglog.parse/1` and egglog as its engine.

  | Module | Over |
  |--------|------|
  | `Loge.Egglog.Language` | `Egglog.parse/1` |
  | `Loge.Egglog.Engines.Egglog` | `Egglog.Program.run/3` in a `Loge.Peer` |

  Both are registered with `Loge` when `:loge_egglog` starts.
  """

  @doc "The modules `:loge_egglog` registers with `Loge`."
  @spec modules() :: [module()]
  def modules, do: [Loge.Egglog.Language, Loge.Egglog.Engines.Egglog]
end
