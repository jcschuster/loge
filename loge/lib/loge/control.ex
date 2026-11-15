defmodule Loge.Control do
  @moduledoc """
  One per-run option of an engine, such as the prover or the time limit, rendered next
  to the editor. Its value reaches `c:Loge.Engine.run/2` under `key`. A control
  configures a run; it never carries part of the problem.

  A `:select` takes its value from `choices`; a `:text` offers them as suggestions
  and accepts any text. Choices are a list, or a function called when the control
  is rendered.

  A consumer reads a value from outside, a form field or a JSON value, through
  `cast/2`, which makes no atom of it.
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

  @doc """
  An external value read as the control's value, or `:error` when it is not one. An
  integer may come as its decimal text, and an empty text unsets an integer control
  without a default. A select value is one of the choices or a choice's string form.

      iex> Loge.Control.cast(%Loge.Control{key: :limit, type: :integer, label: "Limit"}, "7")
      {:ok, 7}
  """
  @spec cast(t(), term()) :: {:ok, term()} | :error
  def cast(%__MODULE__{type: :integer}, value) when is_integer(value), do: {:ok, value}
  def cast(%__MODULE__{type: :integer, default: nil}, ""), do: {:ok, nil}

  def cast(%__MODULE__{type: :integer}, value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> {:ok, integer}
      _other -> :error
    end
  end

  def cast(%__MODULE__{type: :boolean}, value) when is_boolean(value), do: {:ok, value}
  def cast(%__MODULE__{type: :text}, value) when is_binary(value), do: {:ok, value}

  def cast(%__MODULE__{type: :select} = control, value) when not is_nil(value) do
    case Enum.find(choices(control), &(&1 == value or to_string(&1) == value)) do
      nil -> :error
      choice -> {:ok, choice}
    end
  end

  def cast(%__MODULE__{}, _value), do: :error

  @doc "The choices of a control, with dynamic ones resolved."
  @spec choices(t()) :: [term()]
  def choices(%__MODULE__{choices: {:dynamic, choices}}), do: choices.()
  def choices(%__MODULE__{choices: choices}), do: choices
end
