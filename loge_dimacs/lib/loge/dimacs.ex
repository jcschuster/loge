defmodule Loge.Dimacs do
  @moduledoc """
  The DIMACS family for Loge: a language per problem, and solvers for them.

  | Language | Problem | Solvers | Translations |
  |----------|---------|---------|--------------|
  | `Loge.Dimacs.Languages.Cnf` (`:dimacs`) | satisfiability | `Loge.Dimacs.Engines.Clasp`, `Cadical`, `Kissat` | `Tptp`, `Smtlib`, `Asp` |
  | `Loge.Dimacs.Languages.Wcnf` (`:wcnf`) | weighted partial MaxSAT | `Loge.Dimacs.Engines.ClaspMaxsat` | `WcnfAsp` |
  | `Loge.Dimacs.Languages.Qdimacs` (`:qdimacs`) | truth of a quantified Boolean formula | `Loge.Dimacs.Engines.Depqbf` | `QdimacsSmtlib` |

  A translation emits the text of its target itself; the target's package is needed
  only to lint or solve the output.

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
      Loge.Dimacs.Engines.Depqbf,
      Loge.Dimacs.Engines.Tptp,
      Loge.Dimacs.Engines.Smtlib,
      Loge.Dimacs.Engines.Asp,
      Loge.Dimacs.Engines.WcnfAsp,
      Loge.Dimacs.Engines.QdimacsSmtlib
    ]
  end
end
