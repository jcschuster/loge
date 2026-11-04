defmodule KinoLoge do
  @moduledoc """
  Livebook smart cells for the languages and engines registered with `Loge`.

  `KinoLoge.Cell` is the Logic Engine cell, registered with Kino when `:kino_loge`
  starts, and `Loge.Outcome` renders through `KinoLoge.Outcome`. Nothing here knows a
  language: every choice the cell offers comes from `Loge.Registry`.
  """
end
