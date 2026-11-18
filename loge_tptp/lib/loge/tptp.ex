defmodule Loge.Tptp do
  @moduledoc """
  TPTP for Loge: the language over `tptp`, one engine per `atp_client` backend, the
  verifiers of the TPTP World, and the TPTP library.

  | Module | Over |
  |--------|------|
  | `Loge.Tptp.Language` | `Tptp.analyze/2` |
  | `Loge.Tptp.Engines.SystemOnTptp` | `AtpClient.SystemOnTptp` |
  | `Loge.Tptp.Engines.StarExec` | `AtpClient.StarExec` |
  | `Loge.Tptp.Engines.LocalExec` | `AtpClient.LocalExec` |
  | `Loge.Tptp.Engines.Isabelle` | `AtpClient.Isabelle` |
  | `Loge.Tptp.Engines.Verify` | `AtpClient.verify/2` |
  | `Loge.Tptp.Engines.Clausify` | Vampire, an executable |
  | `Loge.Tptp.Engines.Ground`, `Dimacs`, `Prolog`, `Smtlib` | `Loge.Tptp.Formula`, `Loge.Tptp.Clause` |
  | `Loge.Tptp.Engines.Fof`, `Tff`, `Thf`, `Untyped` | the same, between the dialects of TPTP; `Loge.Tptp.Typing` |
  | `Loge.Tptp.Library` | `Tptp.Resolver.Http` |

  All of them are registered with `Loge` when `:loge_tptp` starts.
  """

  @doc "The modules `:loge_tptp` registers with `Loge`."
  @spec modules() :: [module()]
  def modules do
    [
      Loge.Tptp.Language,
      Loge.Tptp.Engines.SystemOnTptp,
      Loge.Tptp.Engines.StarExec,
      Loge.Tptp.Engines.LocalExec,
      Loge.Tptp.Engines.Isabelle,
      Loge.Tptp.Engines.Verify,
      Loge.Tptp.Engines.Clausify,
      Loge.Tptp.Engines.Ground,
      Loge.Tptp.Engines.Dimacs,
      Loge.Tptp.Engines.Prolog,
      Loge.Tptp.Engines.Smtlib,
      Loge.Tptp.Engines.Fof,
      Loge.Tptp.Engines.Tff,
      Loge.Tptp.Engines.Thf,
      Loge.Tptp.Engines.Untyped,
      Loge.Tptp.Library
    ]
  end
end
