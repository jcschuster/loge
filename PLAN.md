# Loge — Execution Plan

Design reference: `OUTLINE.md`. Phases 1 to 4 are ordered by how much new parsing each
needs; phases 2 and 4 can run beside 3. Phases 5 to 9 follow the scope of OUTLINE §0, in
order: core contracts, cells, the existing languages, translations, new formalisms. Each
phase has one gate that must pass before the next starts. Phase 10 needs phases 5 and 6
only and can run beside 7 to 9. Phase 0 is issue-only and nothing waits on its answers.

## Phase 0 — Upstream issues and PRs

Open these first; every item has a fallback inside Loge.

| Repo                       | Change                                                                                                                                                                                                                                                                                                                                                                                              | Size                      | Fallback if declined                                                                        | Status                                                                                                                                            |
| -------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------- | ------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| livebook-dev/livebook      | Issue → PR: `diagnostics` option for the smart-cell editor. `reconfigure_smart_cell(ctx, editor: [diagnostics: [%{from, to, severity, message}]])` → `session.ex` editor-update handler (`handle_info({:runtime_smart_cell_editor_update, …})`, currently applies `:source`, `:intellisense_node`, `:visible`) → client event → `setDiagnostics`. Ask whether offsets or line/column are preferred. | ~60 lines Elixir + ~30 JS | diagnostics listed under the editor (phase 1 default anyway)                                | [x] [#3235](https://github.com/livebook-dev/livebook/pull/3235), open; maintainers chose line/column. Loge no longer waits on it (bundled editor) |
| livebook-dev/kino          | Companion PR: add `:diagnostics` to the `Keyword.validate!` allow-list in `Kino.SmartCell.Server.reconfigure_smart_cell/2` and document it. Must land with the Livebook PR.                                                                                                                                                                                                                         | one line + docs           | —                                                                                           | [x] [#522](https://github.com/livebook-dev/kino/pull/522), open; as above                                                                         |
| livebook-dev/livebook      | PR: TPTP highlighting. `assets/package.json` + `codemirror-lang-tptp ^0.1.1`; regenerate `assets/bun.lock`; `languages.js`: import, `tptpDesc`, add to `markdownDesc.codeLanguages` and `languages`; `theme.js`: style `t.modifier`, `t.labelName`, `t.typeName`, `t.standard(t.variableName)`, `t.logicOperator`. Precedent: commit cbcd6386 (Shell), PR #2772 (Python).                           | ~20 lines + lockfile      | plain-text editor for TPTP                                                                  | [x] [#3234](https://github.com/livebook-dev/livebook/pull/3234), merged; the cell uses its own bundle                                             |
| livebook-dev/livebook      | Later PR: aliases `egglog`, `smt2` on the Scheme legacy mode; `asp`, `prolog`, `dimacs` once modes exist                                                                                                                                                                                                                                                                                            | small                     | —                                                                                           | [ ]                                                                                                                                               |
| davfuenmayor/clingo_elixir | Accept `logger:` in `Clingo.Ast.parse!/2` (passes `nil` today); optional `Clingo.parse/2` collecting logger messages                                                                                                                                                                                                                                                                                | small                     | not needed: `loge_asp` lints through the executable                                         | [ ]                                                                                                                                               |
| davfuenmayor/clingo_elixir | Issue: closing a session whose owner died during grounding segfaults the VM (`p(0). p(X+1) :- p(X).`, kill the owner of `Clingo.with_control/2` mid-`ground!`, then halt); grounding itself cannot be interrupted in libclingo, so the session should outlive the grounder or the docs should say so                                                                                                | report                    | `loge_asp` runs the executable                                                              | [ ]                                                                                                                                               |
| davfuenmayor/egglog_elixir | Return spans structurally from the NIF                                                                                                                                                                                                                                                                                                                                                              | —                         | —                                                                                           | [x] parse errors carry `location` since 45e8e55; type errors still text only                                                                      |
| davfuenmayor/egglog_elixir | Structured locations for type and unbound-name errors, so a lint could report them; and a type-check-only entry point (today types are checked only while running)                                                                                                                                                                                                                                  | small Rust                | parse errors only                                                                           | [ ]                                                                                                                                               |
| davfuenmayor/egglog_elixir | An interruptible run (a flag checked between rule iterations), so an engine can cancel without a peer node                                                                                                                                                                                                                                                                                          | small Rust                | `Loge.Peer` (130 ms per run)                                                                | [ ]                                                                                                                                               |
| davfuenmayor/swi_elixir    | Optional: collect all load-time errors and warnings in `priv/bridge.pl`                                                                                                                                                                                                                                                                                                                             | small Prolog              | not needed (lint via `SWI.query`)                                                           | [ ]                                                                                                                                               |
| davfuenmayor/swi_elixir    | A non-raising pull (`{:ok, bindings} \| :done \| {:error, reason}`) beside the raising `Enumerable`; `SWI.Session` reacts to its owner only between requests                                                                                                                                                                                                                                        | small                     | `Loge.Prolog.Swipl` rescues `SWI.Error` per pull and kills the session from a `Loge.Guard`  | [ ]                                                                                                                                               |
| davfuenmayor/clingo_elixir | Publish to Hex (a Hex package cannot depend on a git dependency, so `loge_dimacs` and `loge_asp` cannot be published before); ship the macOS bundles (`native/` has linux x86_64/aarch64 and windows only)                                                                                                                                                                                          | release                   | none: blocks publishing `loge_dimacs`, `loge_asp` and macOS CI                              | [ ]                                                                                                                                               |
| bitwalker/picosat_elixir   | Run `solve` on a dirty CPU scheduler and make it interruptible (picosat's `picosat_set_interrupt`), so a run can be cancelled; 0.2.3 (2022) blocks a normal scheduler until the solve returns, even after the caller dies                                                                                                                                                                           | small C                   | no Picosat engine; clasp covers DIMACS                                                      | [ ]                                                                                                                                               |
| jcschuster/lang-tptp       | `closedBy`/`openedBy` on the `(` `)` `[` `]` `{` `}` tokens (`@detectDelim` finds none, OUTLINE §7); then raise `codemirror-lang-tptp` in `kino_loge/assets` and rebuild                                                                                                                                                                                                                            | small generator change    | TPTP brackets uncoloured                                                                    | [x] 0.1.3                                                                                                                                         |
| davfuenmayor/rudof_elixir  | Publish to Hex with the native bundles hosted as release assets (its README names their size as the obstacle); bundles beyond linux x86_64                                                                                                                                                                                                                                                          | release                   | none for publishing; `Mix.install` takes the git dependency meanwhile, on linux x86_64 only | [ ]                                                                                                                                               |
| rudof-project/rudof        | Line and column of a parse error as fields of its errors (at 393f45e they are inside `error: String`; the ShEx reader has them as fields before that)                                                                                                                                                                                                                                               | small Rust                | positions read from the message text, as for clingo, z3 and cvc5                            | [ ]                                                                                                                                               |

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

- [x] `Loge.Tptp.Language` over `Tptp.analyze/2` (`Tptp.Analysis` as `native`; spans via `Loge.Range.from_offsets/3`; `editor_language` `"tptp"`, the key of `codemirror-lang-tptp` in the editor bundle)
- [x] No analyzers: `Tptp.analyze/2` applies `Tptp.Lint`, and `tptp` makes TPTP4X obsolete
- [x] Engines, one per AtpClient backend: `Loge.Tptp.Engines.SystemOnTptp` (controls: system select, dynamic from `SystemOnTptp.systems/1`; time limit), `StarExec`, `LocalExec`, `Isabelle` (control: proof method with presets)
- [x] Generated source: core `Loge.Engine.to_source/4` (replaces the per-engine port of `KinoAtpClient.AtpSolver.render_source/2`)
- [x] Error-message table ported from `KinoAtpClient.AtpSolver.format_reason/1` (`Loge.Tptp.Backend.format_error/1`)
- [x] `Loge.Input` impls for `Tptp.File`, `Tptp.Unit`
- [x] Includes: `Loge.Tptp.Includes` (includes map, then `Tptp.Resolver.Http`); findings inside an include placed on its directive; engines send inlined units
- [x] `Application.start/2` registers language, analyzers, engines
- [x] Tests against fixtures; no network in CI (SystemOnTPTP against a local HTTP stub, LocalExec against a fixture prover script)

### `kino_loge`

- [x] `KinoLoge.Cell` (name "Logic Engine"): language/engine selects, controls from `controls/0`, bundled editor, diagnostics drawn in the editor and listed under it; state in `KinoLoge.Setup`
- [x] `KinoLoge.ConfigCell`: form from `config_schema/0` of every registered engine; `verify/1` probe with status indicator; `Loge.configure!/2` and the `configure/1` callback apply the settings; secrets by Livebook secret name
- [x] `Kino.Render` impl for `Loge.Outcome`: verdict from core `Loge.Verdict` (tptp's SZS page texts), views, raw output in an Output tab
- [x] Includes: definitions cell (no engine, `name = Loge.source(...)`); `scan_binding/3` for linting; generated includes from `include_names/1` + `Loge.Variable`
- [x] Debounced lint via `Loge.Run` (`Loge.lint/3`); total `handle_event/3`; source attr persisted on every change
- [x] Decided: Kino 0.19.1 has no self-evaluation API; the cell is evaluated as any cell, no Solve button
- [x] Hand-written JS for the cell chrome; the editor is the one bundle (`assets/editor.js` → `lib/assets/editor.js`)
- [x] Outcome rendering: raw output and text views as terminal text (monospace, bounded height); graph views drawn by `Kino.Mermaid`

### Gate

- [x] All KinoAtpClient features reproduced in a notebook under `notebooks/tptp.livemd` (smoke-test notebook exists; to be checked in Livebook)
- [x] `rg -i tptp kino_loge/lib -g '*.ex'` returns nothing

### Editor (spike done, OUTLINE §7)

- [x] CodeMirror 6 bundle with `codemirror-lang-tptp`, Livebook's dark theme, inline diagnostics, grammar switched with the language
- [x] Collaboration: `@codemirror/collab`, the cell as authority, `KinoLoge.ChangeSet`; convergence simulated, Elixir checked against CodeMirror
- [x] Run in Livebook with two browsers: sync, persistence across restart, notebook shortcuts from inside the editor
- [x] Evaluation right after typing: the `ctx.handleSync` handler resolves when the cell has confirmed the client's edits
- [x] Search and replace (Ctrl+F); brackets coloured by nesting depth from the syntax tree (`closedBy`)
- [x] `.devcontainer` built with Podman; the bundle rebuilt in it
- [x] Highlighted output: `KinoLoge.Code` for text views in a language; TPTP engines emit SZS output blocks as TPTP text
- [x] `{:titled, title, view}` view; an output block is titled by its dataform (`CNFRefutation`, `FiniteModel`)
- [ ] Text views in their language from the other engines, once their grammars exist (clingo and z3 models, Prolog output)
- [ ] Remote cursors and selections
- [ ] Light theme and the user's editor settings (not exposed to the iframe; check what `ctx` offers)
- [ ] CI: build the bundle and fail when `lib/assets/editor.js` differs from the committed one
- [x] Grammars, each a Lezer grammar in its own repository, then one import in `assets/editor.js` and the language's `editor_language/0`: SWI-Prolog, egglog, DIMACS, SMT-LIB, ASP
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
- [x] Engine `Loge.Asp.Engines.Clingo` (`--outf=2`): `models` control (unset: clingo's default, which runs an optimisation to its optimum), `time_limit` (`:timeout`); models view of shown atoms; `OPTIMUM FOUND` adds an `optimum found` badge
- [x] `to_source/2`: covered by core `Loge.Engine.to_source/4`
- [x] Engine ids unique across packages: the DIMACS engine is `Loge.Dimacs.Engines.Clasp` (`:clasp`)
- [x] Includes: `#include` resolves files only; a definitions cell cannot be included yet (needs a language-side resolution like TPTP's). Done in phase 7
- [x] Highlighting: `codemirror-lang-asp`

### Gate

- [x] A second language works with one added dependency and no change to `loge` or `kino_loge` (ASP needed one language-neutral fix in `kino_loge`: an empty integer field unsets a control without a default. Both: `notebooks/dimacs.livemd` and `notebooks/asp.livemd` cells generate, solve and render through `KinoLoge.Setup` and `KinoLoge.Outcome` under `Mix.install`; to be checked in Livebook)

## Phase 3 — Prolog, egglog, local Isabelle

### `loge`

- [x] Decided: no `session/0` callback and no `Loge.SessionSupervisor`; runs are independent, shared resources are node-wide (OUTLINE §5)
- [x] `Loge.Tptp.IsabelleServer`: local Isabelle server started on first use when no password is configured, killed with the node by a Port watchdog; a session per run; Isabelle settings no longer required
- [x] `Loge.Guard`: release outside-BEAM resources when the caller dies (now also used by `loge_asp`)
- [x] `Loge.Peer`: call in a fresh peer node stopped with the caller, for uninterruptible NIFs
- [x] `Loge.Outcome.szs` optional (`nil` where SZS does not describe the result; badge view instead); the cell shows the verdict only when present. Superseded by `Loge.Status` (phase 10)

### `loge_prolog`

- [x] Linter in Prolog (`priv/loge.pl`): `read_term/3` loop over the program file, `op/3` directives applied, syntax errors (all) and singletons on the variable; character offsets converted to byte offsets
- [x] Engine `Loge.Prolog.Engines.Swipl`: fresh `swipl` per run, lint then consult then goal; controls `goal`, `answers` (0 = all), `time_limit` (per answer); badge `true`/`false`/`consulted`, SZS only for `:timeout`; table of bindings written by `term_string/3`; printed output captured as raw
- [x] Cancellation: `Loge.Guard` kills the `swipl` process; tested
- [x] Highlighting: `codemirror-lang-swipl`
- [x] Includes (`:- [defs].`, `:- include(defs).`) from definitions cells. Done in phase 7

### `loge_egglog`

- [x] Linter via `Egglog.parse/1` with its structured location (first parse error; no type errors, see phase 0)
- [x] Engine `Loge.Egglog.Engines.Egglog` over `Egglog.Program` in a `Loge.Peer`; `{:graph, mermaid}` view (`Egglog.Snapshot.to_mermaid/1` of a JSON snapshot) with the `graph` control; badge `completed`/`check failed`, no SZS status; cancellation tested
- [x] Includes (`(include "…")`) from definitions cells. Done in phase 7

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

## Phase 5 — Tasks and outputs (`loge`)

Goal: the contracts of OUTLINE §0 and §3 in core, tested with fakes, before any package
uses them. The former phase 5, an MCP server, is deferred: OUTLINE §10 says what the
libraries hold ready for it, and the cross-cutting list below keeps that tested.

### `loge`

- [x] `t:Loge.Engine.task/0` and `c:Loge.Engine.task/0`; fakes for a solve, a check and a translate engine in `test/support/fakes.ex`
- [x] `Loge.Outcome.output` (`Loge.Source.t() | nil`); `problem` gains `:translation` and `:verification`; `Loge.Verdict.of/2` describes both (a description for every problem kind but `:satisfiability`), with a legend for a translation; `VerifiedBad` in the negative tone
- [x] `Loge.Input` for `Loge.Outcome`: its output, else its raw text with no language
- [x] `Loge.Engine.to_source/4`: `input` as text or as a variable (an atom); `references` with `includes:` and `bind:`; doctests for a bound run, a run on a variable, and includes
- [x] `Loge.Registry.language/1` and `engine/1` (id as an atom or its string form; no atom is made), `translations/0`; `register/1` rejects a second module with an id its kind holds
- [x] `Loge.Control.cast/2`, moved from the private `cast/2` of `KinoLoge.Setup`, with its tests
- [x] Moduledocs of `Loge` and `Loge.Engine` state the three tasks
- [x] Sources carry their includes: `Loge.source/3` with `includes:`, `Loge.Source.to_source/3` with `includes:` and `bind:`, `Loge.Source.closure/2`
- [x] `Loge.run!/3` raises `ArgumentError` for an option that is not a control, a setting or `:includes`, and for an input in a language the engine does not read

### Language packages

- [x] Every engine of phases 1–4 declares `task/0` as `:solve`
- [x] Every time limit is `time_limit`, in seconds: SystemOnTPTP, StarExec and LocalExec renamed, mapped by `Loge.Tptp.Backend.time_limit/2`; the notebooks follow. `:library` stays an option of the TPTP engines' `run/2` and of `analyze/2`, a seam for tests; `Loge.run!/3` does not take it

### Gate

- [x] In `loge`'s tests the outcome of the fake translator is the input of the fake solver through `Loge.run!/3`, and the registry finds both by string id (`test/loge/consumer_test.exs`)
- [x] Cancellation tests unchanged; `mix dialyzer` clean in every package

## Phase 6 — Source cell and Engine cell (`kino_loge`)

Goal: two cells by what they produce (OUTLINE §4), linked by variable names.

- [x] `KinoLoge.Editor`: the collaborative source and the lint loop, taken out of `KinoLoge.Cell`; both cells use it
- [x] `KinoLoge.SourceCell` ("Logic Source"): language, variable name (default from `Kino.SmartCell.prefixed_var_name/2`), editor, diagnostics; source `name = Loge.source(:lang, "…", includes: %{…})`; a setup struct of its own (`KinoLoge.SourceSetup`)
- [x] `KinoLoge.Cell` always has an engine: the `engine: nil` clauses and the definitions mode leave `KinoLoge.Setup` and `cell.js`; only languages with an engine are offered
- [x] Engine select grouped by task; a translation's option names its target language
- [x] Input: this cell's editor, or a bound input of a language the engine accepts (a source, or an outcome with an output), shown read-only; attr `"input"`; a chosen input no longer bound stays listed as not bound; the select is hidden while the editor is the only choice
- [x] Result name, optional; attr `"variable"`; source `name = Loge.run!(…)`
- [x] `KinoLoge.Setup` reads ids and control values through `Loge.Registry.language/1`, `engine/1` and `Loge.Control.cast/2`
- [x] `KinoLoge.Outcome`: the output as text in its language, after the views; a translation's verdict with the legend "Ax: the input, C: the output"
- [x] JS for both cells (`cell.js`, `source_cell.js`, shared `editing.js`), driven in jsdom against a stand-in for the cell; the bundle is unchanged (its read-only `viewer()` shows a bound input), so not rebuilt
- [x] `loge_tptp` resolves includes against `Loge.Source.closure/2`, so a source run or included from any cell brings its own includes
- [x] Notebooks: definitions cells become Source cells. No migration code; the notebooks in `notebooks/` are regenerated (the stored source of every TPTP cell equals the one its attrs generate)

### Gate

- [x] `rg -i tptp kino_loge/lib -g '*.ex'` returns nothing
- [ ] In Livebook: a Source cell and an Engine cell that includes it; an Engine cell whose input is another's result; editing the first marks the second stale (to be checked in Livebook)

## Phase 7 — Existing languages on the new contracts

Goal: no part of a problem outside a source, and results that flow on, with the six
languages that exist.

### `loge_tptp`

- [x] Prover outcomes carry `output`: the derivation of a solved problem, else its interpretation, as TPTP source (`AtpClient.Result.derivation/1`, `interpretation/1`); the text views of what the system printed remain only when neither reads
- [x] `Loge.Tptp.Engines.Verify`, task `:check`, over `AtpClient.verify/2`: GDV for a derivation, AGMV for an interpretation; `:verified_good` or `:verified_bad`, `problem: :verification`; tests against a local HTTP stub. Not run against SystemOnTSTP itself
- [x] Before that: read in `deps/atp_client` how `AtpClient.verify/2` is given a derivation or an interpretation that arrives as text. It is not: it takes a `Tptp.Derivation`, an `AtpClient.Interpretation` or a `Result`. The engine parses the text and sends what `AtpClient.Interpretation.from_file/2` reads as an interpretation, the rest as a `Tptp.Derivation`

### `loge_prolog`

- [x] Queries are the `?- Goal.` terms of the source, answered in order; the `goal` control goes; one `{:titled, "?- Goal.", {:table, …}}` view per query with bindings, and with several queries a badge for each without; a source without a query is consulted only. One query gives `:yes`, `:no` or `:timeout`, none or several `:success`; a query that raises ends the run with `{:error, {:prolog, message}}`
- [x] `priv/loge.pl` reports the position of each query's goal, so the engine consults the rest and asks each query. The bridge consults paths only and cannot skip terms (`SWI.load/3`, `bridge.pl`), so a `user:term_expansion/2` clause drops the queries while consulting; the lint no longer reports a query's variables as singletons
- [x] Includes from Source cells (the open item of phase 3): `Loge.Prolog.Includes` reads `:- [name].`, `include/1`, `consult/1`, `ensure_loaded/1`; each source of the closure whose name is a word is written as `<name>.pl` beside the program

### `loge_asp`, `loge_egglog`

- [x] Includes from Source cells (the open items of phases 2 and 3): `Loge.Asp.Includes` and `Loge.Egglog.Includes` read the directives; the sources are written beside the program (`Loge.Executable` gains `:files` and a directory per run) or into egglog's working directory, a directory of the run's in its peer; the ASP lint grounds with them

### Gate

- [ ] `notebooks/demo.livemd`: prove a TPTP problem, bind the result, verify it in a second cell; a Prolog program in a Source cell and two cells that include it and ask one query each. The cells are there, their code regenerated from their attrs with each cell's `to_source/1`; outside Livebook the Prolog, ASP, egglog and DIMACS cells of `demo`, `prolog`, `asp` and `egglog` were evaluated in order and gave the expected verdicts. Not run: the SystemOnTPTP and Verify cells (remote services), Isabelle and z3 (not installed here). To be checked in Livebook
- [x] No control holds part of a problem (the Prolog `goal` was the one)

## Phase 8 — Translations, verified

Goal: the first translations (OUTLINE §8) in Elixir, each with its verification
(OUTLINE §9). A translation is not done before its record exists.

### Before the first translation

- [ ] Send GDV a hand-written clausification derivation in E's annotation style through `AtpClient.verify/2`, and note which rule names and `status` values it accepts for Skolemisation and definition steps

### `loge_tptp`

- [ ] `Loge.Tptp.Formula`: terms, atoms, connectives, quantifiers; read from `Tptp.Node`, printed through `Tptp.Printer`; round-trip property
- [ ] `Loge.Tptp.Engines.Clausify`: FOF → CNF. Negated conjecture, simplification, negation normal form, variable renaming, Skolemisation, naming of subformulas (a control), distribution; `details.derivation`
- [ ] `Loge.Tptp.Engines.Ground`: clauses with no function symbol of arity above 0 → their ground instances over the constants
- [ ] `Loge.Tptp.Engines.Dimacs`: ground clauses without equality → DIMACS, with the atom table
- [ ] `:inappropriate` with diagnostics for input outside each fragment
- [ ] Properties with StreamData (a test-only dependency), in `mix test`
- [ ] Verification suite tagged `:verification`, excluded in `test_helper.exs`: derivation (GDV), status (TPTP headers), differential (ECNF, VCNF, EGround)
- [ ] `loge_tptp/VERIFICATION.md` for the version to be published

### Gate

- [ ] `notebooks/demo.livemd`: one FOF problem whose Skolemisation introduces constants only, through Clausify, Ground, Dimacs and clasp in four cells; the SAT verdict agrees with a prover's on the original
- [ ] The record shows no disagreement

## Phase 9 — Course formalisms

Goal: modal and description logics (OUTLINE §0). Each is added without a change to
`loge` or `kino_loge`. The semantic web is phase 10.

### Modal logic (`loge_tptp`)

- [ ] Find which SystemOnTPTP systems take non-classical TPTP and offer them for it
- [ ] `Loge.Tptp.Engines.Embed`: non-classical TPTP → THF by shallow embedding, in Elixir; reference ATFLET; verified as in phase 8, on the non-classical problems of the TPTP library
- [ ] The standard translation of propositional modal logic into FOF, if the course uses it

### Description logics

- [ ] Decide the concrete syntax and the reasoner (open question below)
- [ ] Translations between description logic, modal logic and first-order logic as the course states them

### Gate

- [ ] Each formalism has a section in `notebooks/demo.livemd` and a smoke-test notebook

## Phase 10 — Statuses, roles and the semantic web

Goal: Turtle, SPARQL, SHACL and ShEx (OUTLINE §0, §3) through rudof_elixir. Needs phases
5 and 6 only. Statuses and roles are the two core changes it brings; both come first.

Not in this phase: RDFS and OWL entailment (rudof has none), validation against an
endpoint, RDF syntaxes other than Turtle.

### Statuses (`loge`, every package)

- [x] `Loge.Status`: the ontology's values and `:yes`, `:no`, `:conformant`, `:nonconformant`, each with name, description and tone (OUTLINE §3)
- [x] `Loge.Outcome.szs` becomes `status`, never `nil`; `Loge.Verdict.of/2` and `KinoLoge.Outcome` read `Loge.Status`; the `preserves` of a task is a `Loge.Status.t()`
- [x] `loge_prolog`: `true` → `:yes`, `false` → `:no`, `consulted` → `:success`. `loge_egglog`: `completed` → `:success`, `check failed` → `:no`. `loge_smtlib`: a script with no or several `check-sat` → `:success`; one `check-sat` the solver stopped before answering → `:input_error` with a solver error, `:stopped` without. Their verdict badges go; clingo's `optimum found` stays
- [x] Notebooks: no generated source changed, so none regenerated; the expected verdicts in their prose and `outcome.status` in `demo.livemd` updated (to be checked in Livebook); `mix dialyzer` clean in every package

### Roles (`loge`, `kino_loge`)

- [ ] `Loge.Role` and `c:Loge.Engine.roles/0`; every existing engine returns `[]`
- [ ] `Loge.run!/3` takes role keys as options, and raises `ArgumentError` for a missing required role and for a value in a language the role does not list
- [ ] `roles:` in `Loge.Engine.to_source/4`
- [ ] `KinoLoge.Cell`: one select per role over the bound inputs of its languages, the widget of the input select; attr `"roles"`
- [ ] A fake engine with a required and an optional role in both `test/support/fakes.ex`

### Probe (the agent determines; record the findings in OUTLINE §6)

Run with a checkout of rudof_elixir as a path dependency of a scratch project.

- [ ] The linux x86_64 bundle loads in this environment (NixOS, OTP 29) and in `.devcontainer`; rudof_elixir's own `mix test` passes
- [ ] Time of a `Loge.Peer` start plus a first `Rudof` call, and of a parse in the node itself; whether a killed caller leaves the node sound
- [ ] The error text of each reader for a broken input: Turtle, SPARQL, ShExC, ShapeMap. Where line and column stand in it, their base and their unit
- [ ] The shape of the diagnostics of `Rudof.Session.check_shex_schema/3`, and of the maps `Rudof.query/3`, `Rudof.validate_shacl/3` and `Rudof.validate_shex/4` return
- [ ] Against which prefixes a shape map is read: its own, the schema's, the data's. If the schema's or the data's, `c:Loge.Language.analyze/2` receives roles as it receives includes
- [ ] Whether `Rudof.validate_shacl/3` with one text as data and as shapes validates a graph against the shapes it contains
- [ ] Which endpoint names rudof's default configuration knows, and how a URL is given
- [ ] From these: lint in the node or in a peer; how a time limit ends a run

### `loge_turtle`

- [ ] `Loge.Turtle.Language` (`:turtle`, `.ttl`): lint by rudof's reader, its first error, positioned from the message
- [ ] `Loge.Turtle.Engines.Shacl`, task `:check`: the source is the shapes graph, the role `data` is optional; `:conformant` or `:nonconformant`; a table of the results (focus node, path, value, shape, constraint, severity, message); in a `Loge.Peer`

### `loge_sparql`

- [ ] `Loge.Sparql.Language` (`:sparql`, `.rq`): lint by rudof's query reader
- [ ] `Loge.Sparql.Engines.Query`, task `:solve`: required role `data`. `SELECT` → a table, and `:yes` or `:no`; `ASK` → `:yes` or `:no`; `CONSTRUCT` and `DESCRIBE` → `:success` with the graph as Turtle `output`
- [ ] `Loge.Sparql.Engines.Endpoint`: the same on an endpoint named by an `endpoint` control (a `:text` with the known names as suggestions); no role

### `loge_shex`

- [ ] `Loge.Shex.Language` (`:shex`, `.shex`) and the shape map language (`:shapemap`, `.sm`), both linted by rudof's readers. One package, two languages: a shape map is ShEx's own notation and has no use without a schema
- [ ] `Loge.Shex.Engines.Validate`, task `:check`: the source is the shape map, the roles `schema` and `data` are required; `:conformant` when every pair is, else `:nonconformant`; a table of node, shape, status and details

### Editor

- [ ] Evaluate `codemirror-lang-sparql` and `codemirror-lang-turtle` against what the bundle needs (highlight tags, `closedBy`/`openedBy` on brackets); take, fork or write
- [ ] ShExC and ShapeMap grammars, each a Lezer grammar in its own repository, as the five of phase 1
- [ ] Imports in `kino_loge/assets/editor.js`; `npm run build`

### Gate

- [ ] `notebooks/rdf.livemd`: a Turtle Source cell; a `SELECT` over it; a `CONSTRUCT` bound to a name and queried by a further cell; SHACL with a `data` role and with the shapes inside the data; a ShEx schema in a Source cell with two shape-map cells; one endpoint query
- [ ] A section of `notebooks/demo.livemd`
- [ ] The three packages needed no change in `loge` or `kino_loge` beyond statuses and roles
- [ ] Tests that load the NIF are tagged and excluded where the bundle does not load; CI runs them on linux x86_64

## Cross-cutting (from day one)

- [ ] `notebooks/<language>.livemd` template per language with a pinned `Mix.install`
- [x] `notebooks/demo.livemd`: guided tour (cell anatomy, settings, TPTP with includes and local Isabelle, one puzzle in ASP/SMT-LIB/Prolog, egglog e-graph, linting, the Elixir API with a CNF built as data); imported with Livebook's own `LiveMarkdown.Import` and every cell evaluated in order (z3 from a scratch download); to be checked in Livebook
- [ ] CI matrix: package × {ubuntu x86_64, ubuntu aarch64, macos}; NIF-bundled engines (clingo, SWI) exercised per OS
- [ ] Clean-machine smoke test before each course
- [x] Shared kill-with-caller in `loge`: `Loge.Executable` for command-line tools, `Loge.Guard` for processes holding a Port (`loge_prolog`, `Loge.Peer`)
- [ ] Run DIMACS through the `clingo` executable or a `Loge.Peer`, so grounding is cancellable too
- [ ] Before publishing a package that has a translation: `mix test --only verification`, and its `VERIFICATION.md` for that version with no disagreement (OUTLINE §9)
- [x] The consumer contract of OUTLINE §10 holds: a test in `loge` discovers, configures, lints and runs fake modules through the registry by string ids, and `loge` has no Kino dependency (`loge/test/loge/consumer_test.exs`)

## Open questions

- [x] Smart-cell self-evaluation API in Kino: does not exist (0.19.1)
- [x] SZS vocabulary for non-ATP outcomes: not everything maps; `szs: nil` with a badge for Prolog answers and egglog runs. Superseded by `Loge.Status` (phase 10)
- [x] SZS descriptions for satisfiability problems: they speak of Ax and C, so `Loge.Outcome.problem` is `:satisfiability` for DIMACS, ASP and SMT-LIB and their verdict has no description; one status vocabulary, no per-language labels
- [x] Sessions: dropped (OUTLINE §5)
- [x] Livebook maintainers' stance on smart-cell-only languages: not asked; niche languages are highlighted by the bundled editor instead
- [x] Exact clingo message text at runtime: observed, OUTLINE §6
- [x] setup-beam pair for CI: Elixir 1.20, OTP 29 (`clingo_elixir`'s bundled NIF is built against OTP 29 headers, NIF 2.18)
- [x] Cell types per task (query, solve, validate): no. Two cells by what they produce; the task is the engine's (OUTLINE §4)
- [x] A behaviour of its own for translations: no. A translation is an engine whose outcome carries a source (OUTLINE §3, §8)
- [x] DPLL as an algorithm to show, and a Datalog language: out of scope (OUTLINE §0)
- [x] Where the formula type for translations lives: in `loge_tptp`, as `Loge.Tptp.Formula` (OUTLINE §8)
- [x] How SZS statuses are read is Loge's own decision: Ax of a TPTP problem is its axioms with the negated conjecture; across logics each side has its models in its own logic (OUTLINE §8)
- [x] Loge's own statuses: a status type, `Loge.Status`, holding the ontology's values and Loge's own; every outcome has one (OUTLINE §3, phase 10)
- [ ] Rules for carrying a verdict back along a translation: not written, not scheduled
- [ ] Equality in `Ground` and `Dimacs`: reject it, or add the ground instances of the equality axioms
- [ ] Description logics: concrete syntax (OWL functional syntax, Manchester syntax, a TPTP encoding) and reasoner
- [x] ShEx shape map: the source of the ShEx engine and a language of `loge_shex`; schema and data are its roles (OUTLINE §3)
- [x] Semantic web packages: one per language, `loge_turtle`, `loge_sparql`, `loge_shex`; SHACL is an engine of `loge_turtle`, and `loge_shex` holds ShExC with its shape maps
- [x] SPARQL on an endpoint: an engine of its own with an `endpoint` control, no role
