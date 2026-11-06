defmodule Loge.Dimacs do
  @moduledoc """
  DIMACS CNF for Loge: the language over `Loge.Dimacs.Cnf` and a SAT engine.

  | Module | Over |
  |--------|------|
  | `Loge.Dimacs.Language` | `Loge.Dimacs.Cnf.parse/1` |
  | `Loge.Dimacs.Engines.Clasp` | `Clingo.Dimacs` |

  Both are registered with `Loge` when `:loge_dimacs` starts.
  """

  @doc "The modules `:loge_dimacs` registers with `Loge`."
  @spec modules() :: [module()]
  def modules, do: [Loge.Dimacs.Language, Loge.Dimacs.Engines.Clasp]
end
