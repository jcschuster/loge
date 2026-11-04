defmodule Loge.Tptp do
  @moduledoc """
  TPTP for Loge: the language over `tptp` and one engine per `atp_client` backend.

  | Module | Over |
  |--------|------|
  | `Loge.Tptp.Language` | `Tptp.analyze/2` |
  | `Loge.Tptp.Engines.SystemOnTptp` | `AtpClient.SystemOnTptp` |
  | `Loge.Tptp.Engines.StarExec` | `AtpClient.StarExec` |
  | `Loge.Tptp.Engines.LocalExec` | `AtpClient.LocalExec` |
  | `Loge.Tptp.Engines.Isabelle` | `AtpClient.Isabelle` |

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
      Loge.Tptp.Engines.Isabelle
    ]
  end
end
