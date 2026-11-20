absent =
  for tool <- [:isabelle, :vampire],
      is_nil(System.find_executable(Atom.to_string(tool))),
      do: tool

ExUnit.start(exclude: [:verification | absent])
