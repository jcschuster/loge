# Loge — Execution Plan

Design reference: `OUTLINE.md`. Phases are ordered by how much new parsing each needs;
phases 2 and 4 can run beside 3. Each phase has one gate that must pass before the next
starts. Phase 0 is issue-only and nothing waits on its answers.

## Phase 0 — Upstream issues and PRs

Open these first; every item has a fallback inside Loge.

| Repo                       | Change                                                                                                                                                                                                                                                                                                                                                                                              | Size                                               | Fallback if declined                                         | Status |
| -------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------- | ------------------------------------------------------------ | ------ |
| livebook-dev/livebook      | Issue → PR: `diagnostics` option for the smart-cell editor. `reconfigure_smart_cell(ctx, editor: [diagnostics: [%{from, to, severity, message}]])` → `session.ex` editor-update handler (`handle_info({:runtime_smart_cell_editor_update, …})`, currently applies `:source`, `:intellisense_node`, `:visible`) → client event → `setDiagnostics`. Ask whether offsets or line/column are preferred. | ~60 lines Elixir + ~30 JS                          | diagnostics listed under the editor (phase 1 default anyway) | [x] [#3235](https://github.com/livebook-dev/livebook/pull/3235), open; maintainers chose line/column |
| livebook-dev/kino          | Companion PR: add `:diagnostics` to the `Keyword.validate!` allow-list in `Kino.SmartCell.Server.reconfigure_smart_cell/2` and document it. Must land with the Livebook PR.                                                                                                                                                                                                                         | one line + docs                                    | —                                                            | [x] [#522](https://github.com/livebook-dev/kino/pull/522), open |
| livebook-dev/livebook      | PR: TPTP highlighting. `assets/package.json` + `codemirror-lang-tptp ^0.1.1`; regenerate `assets/bun.lock`; `languages.js`: import, `tptpDesc`, add to `markdownDesc.codeLanguages` and `languages`; `theme.js`: style `t.modifier`, `t.labelName`, `t.typeName`, `t.standard(t.variableName)`, `t.logicOperator`. Precedent: commit cbcd6386 (Shell), PR #2772 (Python).                           | ~20 lines + lockfile                               | plain-text editor for TPTP                                   | [x] [#3234](https://github.com/livebook-dev/livebook/pull/3234), open |
| livebook-dev/livebook      | Later PR: aliases `egglog`, `smt2` on the Scheme legacy mode; `asp`, `prolog`, `dimacs` once modes exist                                                                                                                                                                                                                                                                                            | small                                              | —                                                            | [ ]    |
| davfuenmayor/clingo_elixir | Accept `logger:` in `Clingo.Ast.parse!/2` (passes `nil` today); optional `Clingo.parse/2` collecting logger messages                                                                                                                                                                                                                                                                                | small                                              | not needed: `loge_asp` lints through the executable            | [ ]    |
| davfuenmayor/clingo_elixir | Issue: closing a session whose owner died during grounding segfaults the VM (`p(0). p(X+1) :- p(X).`, kill the owner of `Clingo.with_control/2` mid-`ground!`, then halt); grounding itself cannot be interrupted in libclingo, so the session should outlive the grounder or the docs should say so | report | `loge_asp` runs the executable | [ ] |
| davfuenmayor/egglog_elixir | Return spans structurally from the NIF: `ParseError(Span::Egglog{i,j}, msg)` → `{:error, {:invalid_theory, msg, %{from: i, to: j}}}`; same for span-carrying type errors                                                                                                                                                                                                                            | ~40 lines Rust in `native/egglog_nif/src/error.rs` | regex on `In L:C-C2:` / `In L:C-L2:C2:`                      | [ ]    |
| davfuenmayor/swi_elixir    | Optional: collect all load-time errors and warnings in `priv/bridge.pl`                                                                                                                                                                                                                                                                                                                             | small Prolog                                       | not needed (lint via `SWI.query`)                            | [ ]    |
| davfuenmayor/clingo_elixir | Publish to Hex (a Hex package cannot depend on a git dependency, so `loge_dimacs` and `loge_asp` cannot be published before); ship the macOS bundles (`native/` has linux x86_64/aarch64 and windows only) | release | none: blocks publishing `loge_dimacs`, `loge_asp` and macOS CI | [ ] |
| bitwalker/picosat_elixir   | Run `solve` on a dirty CPU scheduler and make it interruptible (picosat's `picosat_set_interrupt`), so a run can be cancelled; 0.2.3 (2022) blocks a normal scheduler until the solve returns, even after the caller dies | small C | no Picosat engine; clasp covers DIMACS | [ ] |

Not PR targets: `codemirror/legacy-modes` (ports CM5 modes only), `SirBogman/codemirror-lang-prolog`
(fork after evaluation), potassco/clingo, egraphs-good/egglog.

## Phase 1 — Core + TPTP parity

Goal: everything KinoAtpClient does, on the new architecture, with no TPTP-specific code
in `kino_loge`.

### `loge`

- [x] `Loge.Language`, `Loge.Analyzer`, `Loge.Engine` behaviours with typespecs and moduledocs (see OUTLINE §3)
- [x] `Loge.Input` protocol (+ `BitString` impl)
- [x] `Loge.Diagnostic`, `Loge.Range` (Kino line/column format, `from_offsets/3`), `Loge.Analysis`, `Loge.Outcome`, `Loge.Config.Field`, `Loge.Control`
- [x] `Loge.Analyzer.run_all/3` with crash containment
- [x] `Loge.Registry` (config + `Loge.register/1`; `:persistent_term`; `Code.ensure_loaded?` guards)
- [x] `Loge.Run` (`Task.Supervisor`; `async/1` cancels the work when the caller dies)
- [x] `Loge.Application` registering configured modules and starting `Loge.Run`
- [x] ExUnit: fake language + fake engine exercising registry, run_all containment, cancellation-on-death
- [x] Includes: `Loge.Source`, `Loge.source/2`, `includes:` option, `Loge.Engine.to_source/4` with binding variables
- [x] `Loge.run!/3`, `Loge.Error`, `Loge.Engine.to_source/4`; `format_error/1` callback replaces per-engine `to_source/2`
- [x] Published docs skeleton (`ex_doc`), `mix format`, `--warnings-as-errors`

### `loge_tptp`

- [x] `Loge.Tptp.Language` over `Tptp.analyze/2` (`Tptp.Analysis` as `native`; spans via `Loge.Range.from_offsets/3`; `editor_language`: check whether Livebook matches `"tptp"` against #3234's `"TPTP"` case-insensitively)
- [x] No analyzers: `Tptp.analyze/2` applies `Tptp.Lint`, and `tptp` makes TPTP4X obsolete
- [x] Engines, one per AtpClient backend: `Loge.Tptp.Engines.SystemOnTptp` (controls: system select, dynamic from `SystemOnTptp.systems/1`; time limit), `StarExec`, `LocalExec`, `Isabelle` (control: proof method with presets)
- [x] Generated source: core `Loge.Engine.to_source/4` (replaces the per-engine port of `KinoAtpClient.AtpSolver.render_source/2`)
- [x] Error-message table ported from `KinoAtpClient.AtpSolver.format_reason/1` (`Loge.Tptp.Backend.format_error/1`)
- [x] `Loge.Input` impls for `Tptp.File`, `Tptp.Unit`
- [x] Includes: `Loge.Tptp.Includes` (includes map, then `Tptp.Resolver.Http`); findings inside an include placed on its directive; engines send inlined units
- [x] `Application.start/2` registers language, analyzers, engines
- [x] Tests against fixtures; no network in CI (SystemOnTPTP against a local HTTP stub, LocalExec against a fixture prover script)

### `kino_loge`

- [x] `KinoLoge.Cell` (name "Logic Engine"): managed editor, language/engine selects, controls from `controls/0`, diagnostics listed under the editor; state in `KinoLoge.Setup`
- [ ] Inline diagnostics via `reconfigure_smart_cell(editor: [diagnostics:])`, resent in `handle_connect/1`, once #3235/#522 ship
- [x] `KinoLoge.ConfigCell`: form from `config_schema/0` of every registered engine; `verify/1` probe with status indicator; `Loge.configure!/2` and the `configure/1` callback apply the settings; secrets by Livebook secret name
- [x] `Kino.Render` impl for `Loge.Outcome`: verdict from core `Loge.Verdict` (tptp's SZS page texts), views, raw output in an Output tab
- [x] Includes: definitions cell (no engine, `name = Loge.source(...)`); `scan_binding/3` for linting; generated includes from `include_names/1` + `Loge.Variable`
- [x] Debounced lint via `Loge.Run` (`Loge.lint/3`); total `handle_event/3`; source attr persisted on every change
- [x] Decided: Kino 0.19.1 has no self-evaluation API; the cell is evaluated as any cell, no Solve button
- [x] Minimal JS (Kino.JS for the cell chrome only; no editor bundle)

### Gate

- [ ] All KinoAtpClient features reproduced in a notebook under `notebooks/tptp.livemd` (smoke-test notebook exists; to be checked in Livebook)
- [x] `grep -ri tptp kino_loge/lib` returns nothing
- [ ] Publish `loge`, `loge_tptp`, `kino_loge` 0.1.0; KinoAtpClient README points here

## Phase 2 — DIMACS, ASP (cheap breadth)

### `loge_dimacs`

- [x] Lexer/linter in Elixir (header, clause terminators, variable range) with offsets: `Loge.Dimacs.Cnf.parse/1`, codes `DIMACS001`–`DIMACS007`
- [x] Engine `Loge.Dimacs.Engines.Clasp` (`Clingo.Dimacs.solve!` on the formula as `Loge.Dimacs.Cnf` renders it; `models` control, `0` for all); cancellation tested
- [ ] Engine `Loge.Dimacs.Engines.Picosat`: blocked on the picosat_elixir row of phase 0 (no cancellation)
- [x] SZS mapping: satisfiable/unsatisfiable/unknown + `{:models, …}` view (a literal per variable); raw output in SAT competition format

### `loge_asp`

- [x] Linter: grounding by the bundled `clingo` executable (`--outf=3 --solve-limit=0 --time-limit=10`), not the NIF (OUTLINE §6); `Loge.Asp.Messages` reads its messages, `note:` lines as related positions, codes from clingo's `--warn` classes
- [x] `Loge.Asp.Executable`: Port + guardian killing clingo with its caller; tested against an endless grounding
- [x] Engine `Loge.Asp.Engines.Clingo` (`--outf=2`): `models` control (unset: clingo's default, which runs an optimisation to its optimum), `time_limit` (`:timeout`); models view of shown atoms
- [x] `to_source/2`: covered by core `Loge.Engine.to_source/4`
- [x] Engine ids unique across packages: the DIMACS engine is `Loge.Dimacs.Engines.Clasp` (`:clasp`)
- [ ] Includes: `#include` resolves files only; a definitions cell cannot be included yet (needs a language-side resolution like TPTP's)
- [ ] Highlighting: none in Livebook (`editor_language/0` is `nil`)

### Gate

- [ ] A second language works with one added dependency and no change to `loge` or `kino_loge` (ASP needed one language-neutral fix in `kino_loge`: an empty integer field unsets a control without a default. Both: `notebooks/dimacs.livemd` and `notebooks/asp.livemd` cells generate, solve and render through `KinoLoge.Setup` and `KinoLoge.Outcome` under `Mix.install`; to be checked in Livebook)

## Phase 3 — Sessions: Prolog, egglog

### `loge`

- [ ] `session/0` callback, `Loge.SessionSupervisor` (owner-keyed, torn down with owner)
- [ ] Isabelle engine session: local server started on demand when `isabelle` is on PATH (port of `KinoAtpClient.IsabelleRuntime`)

### `loge_prolog`

- [ ] Linter as a Prolog goal: `open_string/2` + `read_term/3` loop (`syntax_errors(dec10)` under a local `message_hook`, `singletons(warning)`, `term_position`, `subterm_positions`, `variable_names`, `comments`, `module`) run via `SWI.query`; convert `stream(_,Line,LinePos,CharNo)` to offsets
- [ ] Engine: consult temp file + goal control; true/false/bindings → SZS + table view
- [ ] Decide on highlighting: evaluate `codemirror-lang-prolog` on SWI syntax; fork or write a mode

### `loge_egglog`

- [ ] Linter via `Egglog.parse/1` (structured span after the upstream PR; regex fallback)
- [ ] Engines: `Program` (stateless), `EGraph` (session); `{:graph, dot}` view via `Egglog.Graphviz`
- [ ] SZS mapping for check passed/failed — decide before freezing `Loge.Outcome`

### Gate

- [ ] A session dies with its owning cell; non-TPTP outcomes render through the closed view set

## Phase 4 — SMT-LIB

### `loge_smtlib`

- [ ] S-expression lexer + command-level lint with offsets
- [ ] Port engines: z3 (`-in -smt2`; parse `(error "line L column C: …")`), cvc5 (`--lang smt2 --produce-models`; `(error "Parse Error: <stdin>:L.C: …")`); binary from PATH/config, no download step
- [ ] Model parsed from `(get-model)` into a table view

### Gate

- [ ] First Port-only engine; reusable as the template for kissat/cadical/Vampire

## Phase 5 — MCP and agents

### `loge_mcp`

- [ ] Tools `list_engines`, `lint(language, source)`, `solve(engine, source, options)`; JSON schema generated from `config_schema/0` + `controls/0`
- [ ] Reuse AtpMcp's transport

### Gate

- [ ] `loge_mcp` has no Kino dependency; the agent framework calls `Loge.Engine.run/2` directly

## Cross-cutting (from day one)

- [ ] `notebooks/<language>.livemd` template per language with a pinned `Mix.install`
- [ ] CI matrix: package × {ubuntu x86_64, ubuntu aarch64, macos}; NIF-bundled engines (clingo, SWI) exercised per OS
- [ ] Clean-machine smoke test before each course
- [ ] Phase 4 (first Port-only engines): move `Loge.Asp.Executable`'s guardian into `loge` as the shared way to run an OS process that dies with its caller; then consider running DIMACS through the `clingo` executable too (clasp's own DIMACS reader, cancellable grounding)

## Open questions

- [x] Smart-cell self-evaluation API in Kino: does not exist (0.19.1)
- [ ] SZS vocabulary for non-ATP outcomes (egglog check, Prolog goal, bindings)
- [ ] Livebook maintainers' stance on smart-cell-only languages (`diagnostics`: line/column, settled in #3235/#522)
- [ ] `codemirror-lang-prolog` SWI coverage
- [x] Exact clingo message text at runtime: observed, OUTLINE §6
- [ ] setup-beam elixir/OTP pair for 1.20 in CI
