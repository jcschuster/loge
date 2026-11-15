defmodule KinoLoge do
  @moduledoc """
  Livebook smart cells for the languages and engines registered with `Loge`.

  Two cells, by what they produce, registered with Kino when `:kino_loge` starts:
  `KinoLoge.SourceCell`, the Logic Source cell, binds a source, and `KinoLoge.Cell`, the
  Logic Engine cell, runs an engine and can bind its outcome. Cells are linked by
  variable names only: a source or an outcome one cell binds is what another includes
  or takes as its input. `KinoLoge.ConfigCell` configures the engines, and
  `Loge.Outcome` renders through `KinoLoge.Outcome`.

  Nothing here knows a language: every choice the cells offer comes from
  `Loge.Registry`.
  """
end
