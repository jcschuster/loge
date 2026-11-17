defmodule Loge.Smtlib do
  @moduledoc """
  SMT-LIB 2.6 for Loge: the language over `Loge.Smtlib.Sexp` and two solvers run as
  OS processes.

  | Module | Over |
  |--------|------|
  | `Loge.Smtlib.Language` | `Loge.Smtlib.Sexp`, `Loge.Smtlib.Commands` |
  | `Loge.Smtlib.Engines.Z3` | the `z3` executable |
  | `Loge.Smtlib.Engines.Cvc5` | the `cvc5` executable |
  | `Loge.Smtlib.Engines.Dimacs` | the `z3` executable, its bit-blasting tactics |
  | `Loge.Smtlib.Engines.Tptp` | `Loge.Smtlib.Sexp` |

  The solvers are not bundled. All of the modules are registered with `Loge` when
  `:loge_smtlib` starts.
  """

  @doc "The modules `:loge_smtlib` registers with `Loge`."
  @spec modules() :: [module()]
  def modules do
    [
      Loge.Smtlib.Language,
      Loge.Smtlib.Engines.Z3,
      Loge.Smtlib.Engines.Cvc5,
      Loge.Smtlib.Engines.Dimacs,
      Loge.Smtlib.Engines.Tptp
    ]
  end
end
