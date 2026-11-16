defmodule Loge.Dimacs do
  @moduledoc """
  The DIMACS family for Loge: a language per problem, and solvers for them.

  | Language | Problem | Engines |
  |----------|---------|---------|
  | `Loge.Dimacs.Languages.Cnf` (`:dimacs`) | satisfiability | `Loge.Dimacs.Engines.Clasp`, `Cadical`, `Kissat` |
  | `Loge.Dimacs.Languages.Wcnf` (`:wcnf`) | weighted partial MaxSAT | `Loge.Dimacs.Engines.ClaspMaxsat` |
  | `Loge.Dimacs.Languages.Qdimacs` (`:qdimacs`) | truth of a quantified Boolean formula | `Loge.Dimacs.Engines.Depqbf` |

  clasp is bundled with `clingo_elixir`; CaDiCaL, Kissat and DepQBF are executables
  found on `PATH` or configured. All of them are registered with `Loge` when
  `:loge_dimacs` starts.
  """

  @doc "The modules `:loge_dimacs` registers with `Loge`."
  @spec modules() :: [module()]
  def modules do
    [
      Loge.Dimacs.Languages.Cnf,
      Loge.Dimacs.Languages.Wcnf,
      Loge.Dimacs.Languages.Qdimacs,
      Loge.Dimacs.Engines.Clasp,
      Loge.Dimacs.Engines.Cadical,
      Loge.Dimacs.Engines.Kissat,
      Loge.Dimacs.Engines.ClaspMaxsat,
      Loge.Dimacs.Engines.Depqbf
    ]
  end
end
