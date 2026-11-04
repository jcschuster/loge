# CLAUDE.md

Loge: Livebook smart cells and Elixir libraries for logic languages. Read `OUTLINE.md`
(design, contracts, verified backend facts) and `PLAN.md` (phases, checklists) before
changing anything. They are the source of truth; update them when a decision changes.

## Objective

Elegance. Every module should read as if it could not have been written any other way.
Nothing hacky, no workarounds, no "for now". If the clean solution needs a change in a
contract or an upstream library, say so instead of routing around it.

## Repository rules

- Monorepo, one mix project per directory, no umbrella. Language packages depend only on
  `loge`; consumers (`kino_loge`, `loge_mcp`) depend only on `loge`. Never cross-link
  language packages.
- `kino_loge` contains no language-specific code. `grep -ri tptp kino_loge/lib` must stay empty.
- Generated cell source (`Loge.Engine.to_source/4`) must run without `kino_loge` installed: one
  `Loge.run!/3` call with named options, no helper modules.
- Package name = module namespace (`loge_tptp` → `Loge.Tptp`).
- Minimum Elixir 1.20.

## Workflow

- Test-driven: write the failing test first, then the smallest implementation that passes,
  then refactor. Every public function has a test; behaviours are tested through a fake
  implementation in `test/support`.
- Before finishing a task run, from the package directory: `mix format`,
  `mix compile --warnings-as-errors`, `mix test`. Run `mix dialyzer` when touching typespecs.
- Never commit or push. When a change is complete, suggest a commit message and stop.
- Report what changed, not full file contents.
- Flag ambiguities instead of resolving them silently. Verify claims about libraries
  against their source in `deps/` before relying on them.

## Elixir

- Behaviours with `@callback` and typespecs; protocols for polymorphism over data;
  structs with `@enforce_keys`; pattern matching over conditionals; pipelines over nesting.
- Supervision: work runs under `Task.Supervisor.async_nolink`; callers monitor `:DOWN`.
  Never `Task.async` from a process whose death loses user state (a smart cell).
- Avoid the documented anti-patterns (hexdocs "Code / Design / Process anti-patterns"):
  no `String.to_atom/1` on external input, no boolean-blindness parameters, no
  primitive obsession, no unrelated multi-clause functions, no GenServer for pure
  computation, no agent-as-global-state, no `try/rescue` for control flow,
  no `Application.get_env` in hot paths (read at init).
- Return tagged tuples; raise only with bang variants. Errors are data.
- Performance: binaries by offset (`binary_part/3`), no intermediate lists in lexers,
  `IO.iodata` for output, streams for large input. Measure with `Benchee` before optimising.
- Small modules with one responsibility. Delete code rather than keep it "in case".

## Documentation and types

- Every public module: `@moduledoc`; every public function: `@doc` and `@spec`; every
  public type: `@type` with `@typedoc`.
- Prose is minimal and specific: what it does, what it returns, which options exist, one
  example when the shape is not obvious. No marketing, no "powerful", "seamless",
  "robust", "comprehensive"; no restating the function name; no emoji; no bullet lists
  of benefits. Write as the `tptp` and `AtpClient` moduledocs are written.
- No code comments. If a line needs a comment, rename or restructure until it does not.
  The one exception is a link to a source that justifies a non-obvious constant or format.

## Environment

- NixOS, fish shell. Fish syntax differs from bash: `set -x VAR value` (not `export`),
  `(cmd)` for substitution (not `$(cmd)`), `; and` / `; or` (not `&&` / `||`),
  `if test …; …; end`. When unsure, run commands through `bash -c '…'`.
- Prefer modern CLI tools: `rg` and `fd` are installed; use them instead of `grep -r` and
  `find`. Install others you need (`sd`, `jq`, `bat`, `delta`, `hyperfine`) with
  `nix-shell -p <pkg>` or `nix profile install nixpkgs#<pkg>`; do not edit the system
  configuration.
- Elixir/Erlang come from the Nix environment; do not install them another way.
