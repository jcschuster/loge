defmodule Loge.Sparql do
  @moduledoc """
  SPARQL for Loge, over rudof (`rudof_elixir`): the language, and queries on a data
  graph or on an endpoint.

  | Module | Over |
  |--------|------|
  | `Loge.Sparql.Language` | `Rudof.Session.load_sparql_query/2` |
  | `Loge.Sparql.Engines.Query` | `Rudof.Session.query/2` on the role `data`, in a `Loge.Peer` |
  | `Loge.Sparql.Engines.Endpoint` | `Rudof.Session.query/2` on an endpoint, in a `Loge.Peer` |

  All three are registered with `Loge` when `:loge_sparql` starts.
  """

  @doc "The modules `:loge_sparql` registers with `Loge`."
  @spec modules() :: [module()]
  def modules,
    do: [Loge.Sparql.Language, Loge.Sparql.Engines.Query, Loge.Sparql.Engines.Endpoint]
end
