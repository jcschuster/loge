defmodule Loge.Control do
  @moduledoc """
  One per-run option of an engine, such as the prover or the time limit, rendered next
  to the editor. Its value reaches `c:Loge.Engine.run/2` under `key`.

  A `:select` takes its `choices` from a list, or from a function called when the
  control is rendered.
  """

  @enforce_keys [:key, :type, :label]
  defstruct [:key, :type, :label, :default, choices: []]

  @typedoc "The input a control is rendered as."
  @type type :: :select | :text | :integer | :boolean

  @typedoc "Fixed choices, or a function returning them when the control is rendered."
  @type choices :: [term()] | {:dynamic, (-> [term()])}

  @typedoc "A run option with its key, input type, label, choices and default."
  @type t :: %__MODULE__{
          key: atom(),
          type: type(),
          label: String.t(),
          choices: choices(),
          default: term()
        }
end
