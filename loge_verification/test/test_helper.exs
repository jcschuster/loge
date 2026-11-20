absent =
  for tool <- [:princess, :vampire, :z3],
      is_nil(System.find_executable(Atom.to_string(tool))),
      do: tool

ExUnit.start(exclude: absent)
