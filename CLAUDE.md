# CLAUDE.md

Loge: Elixir libraries that give logic engines one interface (sources in, an outcome out;
an engine solves, checks or translates), and the Livebook smart cells that use it. Read
`OUTLINE.md` (scope, design, contracts, verified backend facts) and `PLAN.md` (phases,
checklists) before changing anything. They are the source of truth; update them when a
decision changes.

Scope and non-goals are OUTLINE §0. Do not add what it excludes: algorithm
visualisations, a Datalog language, format converters, interactive provers. `loge_mcp` is
not being built; OUTLINE §10 lists what the libraries must keep true for it.

## Objective

Elegance. Every module should read as if it could not have been written any other way.
Nothing hacky, no workarounds, no "for now". If the clean solution needs a change in a
contract or an upstream library, say so instead of routing around it.

## Repository rules

- Monorepo, one mix project per directory, no umbrella. Language packages depend only on
  `loge`; consumers (`kino_loge`, later `loge_mcp`) depend only on `loge`. Never cross-link
  language packages. Nothing in `loge` or a language package depends on Kino or on a
  transport.
- `kino_loge` contains no language-specific Elixir: `rg -i tptp kino_loge/lib -g '*.ex'` must stay
  empty. The grammar table in `kino_loge/assets/editor.js` is the one place that names languages;
  after changing it run `npm run build` there (Node is in `.devcontainer`) and keep the built
  `lib/assets/editor.js`.
- Generated cell source (`Loge.Engine.to_source/4`) must run without `kino_loge` installed: one
  `Loge.run!/3` call with named options, bound to a variable when the cell names its
  result, no helper modules. Cells are linked by variable names only.
- An engine module performs one task: `:solve`, `:check` or `{:translate, to, preserves}`.
  There is no cell and no behaviour per task.
- No control carries part of a problem. A question the language has syntax for is part of
  the source; a reference the language can express is an include; a source the language
  cannot name is a role (OUTLINE §3).
- A translation is written in Elixir, lives in the package of its source language, emits
  the target's text itself and declares the SZS relation it preserves. It calls no
  external tool and no remote service at run time. Input outside its fragment is an
  outcome with `:inappropriate`, never a best effort (OUTLINE §8).
- A consumer makes no atom from external input: ids through `Loge.Registry.language/1`
  and `engine/1`, control values through `Loge.Control.cast/2`, names through
  `Loge.Variable.parse/1`.
- Package name = module namespace (`loge_tptp` → `Loge.Tptp`).
- Minimum Elixir 1.20.

## Workflow

- Test-driven: write the failing test first, then the smallest implementation that passes,
  then refactor. Every public function has a test; behaviours are tested through a fake
  implementation in `test/support`.
- Before finishing a task run, from the package directory: `mix format`,
  `mix compile --warnings-as-errors`, `mix test`. Run `mix dialyzer` when touching typespecs.
- Translations: property tests (StreamData) run in `mix test`. Tests tagged
  `:verification` call remote TPTP tools and read the TPTP library; they are excluded by
  default and from CI. Run them with `mix test --only verification` before a release and
  record the figures in the package's `VERIFICATION.md` (OUTLINE §9). Never weaken, skip
  or delete a failing verification; report the disagreement.
- From phase 5 on, follow PLAN's phase order; a phase is done when its gate passes. Tick
  a checkbox only for what was run, and write "to be checked in Livebook" where it was
  not.
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
  no `String.to_atom/1` on external input (sole exception: `Loge.Variable.parse/1`, which
  parses an include or binding name the user typed as an Elixir variable, as evaluating the
  generated source would), no boolean-blindness parameters, no
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
