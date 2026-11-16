solvers =
  for solver <- [:cadical, :kissat, :depqbf],
      is_nil(System.find_executable(Atom.to_string(solver))),
      do: solver

ExUnit.start(exclude: solvers)
