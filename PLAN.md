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
| davfuenmayor/clingo_elixir | Accept `logger:` in `Clingo.Ast.parse!/2` (passes `nil` today); optional `Clingo.parse/2` collecting logger messages                                                                                                                                                                                                                                                                                | small                                              | `Control.new!(logger:)` + `add!` + `ground!`                 | [ ]    |
| davfuenmayor/egglog_elixir | Return spans structurally from the NIF: `ParseError(Span::Egglog{i,j}, msg)` → `{:error, {:invalid_theory, msg, %{from: i, to: j}}}`; same for span-carrying type errors                                                                                                                                                                                                                            | ~40 lines Rust in `native/egglog_nif/src/error.rs` | regex on `In L:C-C2:` / `In L:C-L2:C2:`                      | [ ]    |
| davfuenmayor/swi_elixir    | Optional: collect all load-time errors and warnings in `priv/bridge.pl`                                                                                                                                                                                                                                                                                                                             | small Prolog                                       | not needed (lint via `SWI.query`)                            | [ ]    |

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

- [ ] `KinoLoge.Cell` (name "Logic Engine"): managed editor, language/engine selects, controls from `controls/0`, inline diagnostics via `reconfigure_smart_cell(editor: [diagnostics:])` (resent in `handle_connect/1`; list under the editor until #3235/#522 ship), Solve = evaluate
- [ ] `KinoLoge.ConfigCell`: form from `config_schema/0` of every registered engine; `verify/1` probe with status indicator
- [ ] `Kino.Render` impl for `Loge.Outcome`: SZS badge + gloss + ontology link (texts from KinoAtpClient `STATUS_LABELS`), views, opt-in raw output
- [ ] Includes: `scan_binding/3` collects variables of the cell's language; definitions cell ("no engine", bound to a variable, source `name = Loge.source(...)`); include names resolved against binding atoms
- [ ] Debounced lint via `Loge.Run`; total `handle_event/3`; source attr persisted on every change
- [ ] Decide: can a smart cell request its own evaluation? If not, Solve button documents the shortcut
- [ ] Minimal JS (Kino.JS for the cell chrome only; no editor bundle)

### Gate

- [ ] All KinoAtpClient features reproduced in a notebook under `notebooks/tptp.livemd`
- [ ] `grep -ri tptp kino_loge/lib` returns nothing
- [ ] Publish `loge`, `loge_tptp`, `kino_loge` 0.1.0; KinoAtpClient README points here

## Phase 2 — DIMACS, ASP (cheap breadth)

### `loge_dimacs`

- [ ] Lexer/linter in Elixir (header, clause terminators, variable range) with offsets
- [ ] Engines: `Loge.Dimacs.Engines.Clingo` (`Clingo.Dimacs.solve!`), `Loge.Dimacs.Engines.Picosat` (clause-list adapter over `picosat_elixir`)
- [ ] SZS mapping: satisfiable/unsatisfiable + `{:models, …}` view

### `loge_asp`

- [ ] Linter: `Control.new!(logger:)` + `add!` + `ground!`; regex `^<block>:(\d+):(\d+)(?:-(?:(\d+):)?(\d+))?: (error|warning|info): (.*)` → diagnostics (multi-line bodies joined)
- [ ] Engine over `Clingo.solve!/2` with `models:` control; models view
- [ ] `to_source/2`

### Gate

- [ ] A second language works with one added dependency and no change to `loge` or `kino_loge`

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

## Open questions

- [ ] Smart-cell self-evaluation API in Kino: exists or not?
- [ ] SZS vocabulary for non-ATP outcomes (egglog check, Prolog goal, bindings)
- [ ] Livebook maintainers' stance on smart-cell-only languages (`diagnostics`: line/column, settled in #3235/#522)
- [ ] `codemirror-lang-prolog` SWI coverage
- [ ] Exact clingo message text at runtime (read from source only)
- [ ] setup-beam elixir/OTP pair for 1.20 in CI
