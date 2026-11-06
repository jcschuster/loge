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
| davfuenmayor/egglog_elixir | Return spans structurally from the NIF | — | — | [x] parse errors carry `location` since 45e8e55; type errors still text only |
| davfuenmayor/egglog_elixir | Structured locations for type and unbound-name errors, so a lint could report them; and a type-check-only entry point (today types are checked only while running) | small Rust | parse errors only | [ ] |
| davfuenmayor/egglog_elixir | An interruptible run (a flag checked between rule iterations), so an engine can cancel without a peer node | small Rust | `Loge.Peer` (130 ms per run) | [ ] |
| davfuenmayor/swi_elixir    | Optional: collect all load-time errors and warnings in `priv/bridge.pl`                                                                                                                                                                                                                                                                                                                             | small Prolog                                       | not needed (lint via `SWI.query`)                            | [ ]    |
| davfuenmayor/swi_elixir    | A non-raising pull (`{:ok, bindings} \| :done \| {:error, reason}`) beside the raising `Enumerable`; `SWI.Session` reacts to its owner only between requests | small | `Loge.Prolog.Swipl` rescues `SWI.Error` per pull and kills the session from a `Loge.Guard` | [ ] |
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
- [x] clingo runs under `Loge.Executable` (killed with its caller or the node; tested in `loge`)
- [x] Engine `Loge.Asp.Engines.Clingo` (`--outf=2`): `models` control (unset: clingo's default, which runs an optimisation to its optimum), `time_limit` (`:timeout`); models view of shown atoms
- [x] `to_source/2`: covered by core `Loge.Engine.to_source/4`
- [x] Engine ids unique across packages: the DIMACS engine is `Loge.Dimacs.Engines.Clasp` (`:clasp`)
- [ ] Includes: `#include` resolves files only; a definitions cell cannot be included yet (needs a language-side resolution like TPTP's)
- [ ] Highlighting: none in Livebook (`editor_language/0` is `nil`)

### Gate

- [ ] A second language works with one added dependency and no change to `loge` or `kino_loge` (ASP needed one language-neutral fix in `kino_loge`: an empty integer field unsets a control without a default. Both: `notebooks/dimacs.livemd` and `notebooks/asp.livemd` cells generate, solve and render through `KinoLoge.Setup` and `KinoLoge.Outcome` under `Mix.install`; to be checked in Livebook)

## Phase 3 — Prolog, egglog, local Isabelle

### `loge`

- [x] Decided: no `session/0` callback and no `Loge.SessionSupervisor`; runs are independent, shared resources are node-wide (OUTLINE §5)
- [x] `Loge.Tptp.IsabelleServer`: local Isabelle server started on first use when no password is configured, killed with the node by a Port watchdog; a session per run; Isabelle settings no longer required
- [x] `Loge.Guard`: release outside-BEAM resources when the caller dies (now also used by `loge_asp`)
- [x] `Loge.Peer`: call in a fresh peer node stopped with the caller, for uninterruptible NIFs
- [x] `Loge.Outcome.szs` optional (`nil` where SZS does not describe the result; badge view instead); the cell shows the verdict only when present

### `loge_prolog`

- [x] Linter in Prolog (`priv/loge.pl`): `read_term/3` loop over the program file, `op/3` directives applied, syntax errors (all) and singletons on the variable; character offsets converted to byte offsets
- [x] Engine `Loge.Prolog.Engines.Swipl`: fresh `swipl` per run, lint then consult then goal; controls `goal`, `answers` (0 = all), `time_limit` (per answer); badge `true`/`false`/`consulted`, SZS only for `:timeout`; table of bindings written by `term_string/3`; printed output captured as raw
- [x] Cancellation: `Loge.Guard` kills the `swipl` process; tested
- [ ] Decide on highlighting: evaluate `codemirror-lang-prolog` on SWI syntax; fork or write a mode
- [ ] Includes (`:- [defs].`, `:- include(defs).`) from definitions cells

### `loge_egglog`

- [x] Linter via `Egglog.parse/1` with its structured location (first parse error; no type errors, see phase 0)
- [x] Engine `Loge.Egglog.Engines.Egglog` over `Egglog.Program` in a `Loge.Peer`; `{:graph, dot}` view with the `graph` control; badge `completed`/`check failed`, no SZS status; cancellation tested
- [ ] Includes (`(include "…")`) from definitions cells

### Gate

- [ ] A cancelled run ends: met for every engine but the DIMACS one (grounding runs to its end); to be checked in Livebook
- [ ] The local Isabelle server is gone after the Livebook runtime stops: tested with `System.halt/0`; to be checked in Livebook
- [ ] Non-TPTP outcomes render through the closed view set: `notebooks/prolog.livemd` and `notebooks/egglog.livemd` cells rendered through `KinoLoge.Outcome` under `Mix.install` with all language packages; to be checked in Livebook

## Phase 4 — SMT-LIB

### `loge_smtlib`

- [x] S-expression reader with byte spans (`Loge.Smtlib.Sexp`, `SMTLIB001`–`005`) + command-level lint (`Loge.Smtlib.Commands`, `SMTLIB101`–`105`; unknown commands are warnings)
- [x] Engines `Loge.Smtlib.Engines.Z3` (`-smt2 <file>`), `Cvc5` (`--lang smt2 --produce-models --incremental <file>`) over `Loge.Executable`; `executable` setting (PATH by default), `time_limit` control killing the solver; solver errors as a diagnostics view positioned from z3's/cvc5's messages
- [x] Responses read as S-expressions: one `check-sat` → SZS; several → table of results, no SZS; models → table views
- [x] Tests against a fake solver; real z3/cvc5 tests tagged and run when on PATH (run here with z3 5.3.3, cvc5 1.4.2)
- [ ] CI: install z3 and cvc5 so the tagged tests run

### Gate

- [x] First Port-only engine; reusable as the template for kissat/cadical/Vampire: `Loge.Executable` in core (also replaces `loge_asp`'s runner; kills the tool when the node halts)

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
- [x] Shared kill-with-caller in `loge`: `Loge.Executable` for command-line tools, `Loge.Guard` for processes holding a Port (`loge_prolog`, `Loge.Peer`)
- [ ] Run DIMACS through the `clingo` executable or a `Loge.Peer`, so grounding is cancellable too

## Open questions

- [x] Smart-cell self-evaluation API in Kino: does not exist (0.19.1)
- [x] SZS vocabulary for non-ATP outcomes: not everything maps; `szs: nil` with a badge for Prolog answers and egglog runs
- [x] Sessions: dropped (OUTLINE §5)
- [ ] Livebook maintainers' stance on smart-cell-only languages (`diagnostics`: line/column, settled in #3235/#522)
- [ ] `codemirror-lang-prolog` SWI coverage
- [x] Exact clingo message text at runtime: observed, OUTLINE §6
- [ ] setup-beam elixir/OTP pair for 1.20 in CI
