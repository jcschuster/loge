defmodule Loge.Role do
  @moduledoc """
  A source an engine needs beside its input, one the input's language has no syntax to
  name: the data graph a SPARQL query or SHACL shapes are asked of, the schema and the
  data of a ShEx shape map. The input holds what is asked; a role holds what it is
  asked of.

  An engine lists its roles in `c:Loge.Engine.roles/0`. A role's value reaches
  `c:Loge.Engine.run/2` under `key` as a `Loge.Input`, in one of `languages`; role keys
  and control keys are disjoint. `Loge.run!/3` raises for a required role that is
  missing and for a value in another language. A consumer offers the bound inputs of
  the role's languages.
  """

  @enforce_keys [:key, :label, :languages, :required?]
  defstruct @enforce_keys

  @typedoc "A role with its option key, label, the ids of its languages and whether a run needs it."
  @type t :: %__MODULE__{
          key: atom(),
          label: String.t(),
          languages: [atom()],
          required?: boolean()
        }
end
