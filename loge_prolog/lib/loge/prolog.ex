defmodule Loge.Prolog do
  @moduledoc """
  Prolog for Loge: SWI-Prolog's language and `swipl` as its engine.

  | Module | Over |
  |--------|------|
  | `Loge.Prolog.Language` | `Loge.Prolog.Swipl.lint/2` |
  | `Loge.Prolog.Engines.Swipl` | `Loge.Prolog.Swipl.solve/4` |
  | `Loge.Prolog.Engines.Tptp`, `Asp` | `Loge.Prolog.Program` |

  All run the `swipl` bundled with `swi_elixir` and are registered with `Loge` when
  `:loge_prolog` starts.
  """

  @doc "The modules `:loge_prolog` registers with `Loge`."
  @spec modules() :: [module()]
  def modules do
    [
      Loge.Prolog.Language,
      Loge.Prolog.Engines.Swipl,
      Loge.Prolog.Engines.Tptp,
      Loge.Prolog.Engines.Asp
    ]
  end
end
