solvers =
  for solver <- [:z3, :cvc5], is_nil(System.find_executable(Atom.to_string(solver))), do: solver

ExUnit.start(exclude: solvers)
