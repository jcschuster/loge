defmodule Loge.Config.Field do
  @moduledoc """
  One setting of an engine that holds across runs, such as a credential or a binary
  path, in a shape a form can render directly. The shape of `AtpClient.Config.Field`.

  Engines declare these in `c:Loge.Engine.config_schema/0`; a form lays them out by
  `group` and masks those with `secret?`.
  """

  @enforce_keys [:key, :type, :required?, :group]
  defstruct [:key, :type, :required?, :group, :default, :label, :doc, secret?: false]

  @typedoc "The value's type; a form maps it to an input. Values are not coerced."
  @type type :: :string | :integer | :boolean | :string_list

  @typedoc """
  `:connection` settings are needed to reach the engine and checked by
  `c:Loge.Engine.verify/1`; `:defaults` are used by runs; `:advanced` are rarely
  touched.
  """
  @type group :: :connection | :defaults | :advanced

  @typedoc "A setting with its key, type, layout group and presentation."
  @type t :: %__MODULE__{
          key: atom(),
          type: type(),
          required?: boolean(),
          group: group(),
          default: term(),
          label: String.t() | nil,
          doc: String.t() | nil,
          secret?: boolean()
        }
end
