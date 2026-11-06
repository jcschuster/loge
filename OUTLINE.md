# Loge — Design Outline

Loge ("Logic Engines") is a Livebook smart cell and a set of Elixir libraries for
editing, linting and solving problems in logic languages (TPTP, DIMACS, ASP, Prolog,
egglog, SMT-LIB) through pluggable engines. It succeeds
[KinoAtpClient](https://github.com/jcschuster/KinoAtpClient).

This file is the design reference. `PLAN.md` holds the phased execution plan.

## 1. Decisions (fixed)

| Decision          | Choice                                                                                                                                         |
| ----------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| Editor            | Livebook-managed smart-cell editor (`editor:` option), not a custom CodeMirror/Monaco bundle.                                                  |
| Highlighting      | Editor-side only; provided by Livebook's language list. TPTP via livebook#3234 (`codemirror-lang-tptp`); others later. No per-package JS.      |
| Positions         | Diagnostics carry line/column ranges in Kino's smart-cell diagnostics format (kino#522): 1-based, columns in UTF-16 code units.                |
| Linting / solving | Extensible from Elixir through behaviours; each language is its own Hex package.                                                               |
| Verdicts          | A `Loge.Outcome` carries an SZS status (`Tptp.Szs.Ontology.t()`) where the ontology describes the result, `nil` otherwise (a badge view states it). |
| Solve             | Livebook's own cell evaluation (Kino has no API for a cell to evaluate itself). Raw output is the outcome's Output tab.                          |
| Input             | `Loge.Input` protocol (mirrors `AtpClient.Input`).                                                                                             |
| Minimum Elixir    | `~> 1.20`.                                                                                                                                     |
| Naming            | Hex package name = module namespace: `loge` → `Loge`, `loge_tptp` → `Loge.Tptp`, `kino_loge` → `KinoLoge`.                                     |
| Repo              | Monorepo, one mix project per directory, no umbrella (Nx pattern).                                                                             |

## 2. Repository layout

```
loge/                       this repo
  OUTLINE.md  PLAN.md  README.md  .formatter.exs  .gitignore
  loge/                     core: behaviours, registry, structs, run supervision. Deps: tptp (SZS ontology).
  loge_tptp/                Language + analyzers + engines for TPTP. Deps: loge, tptp, atp_client.
  kino_loge/                Smart cells and Kino.Render. Deps: loge, kino.
  loge_dimacs/  (phase 2)   Deps: loge, clingo_elixir.
  loge_asp/     (phase 2)   Deps: loge, clingo_elixir.
  loge_prolog/  (phase 3)   Deps: loge, swi_elixir.
  loge_egglog/  (phase 3)   Deps: loge, egglog_elixir.
  loge_smtlib/  (phase 4)   Deps: loge only; z3/cvc5 executables via Loge.Executable.
  loge_mcp/     (phase 5)   Deps: loge + MCP transport.
  notebooks/                one template notebook per language (pinned Mix.install).
  .github/workflows/ci.yml  matrix: package × {linux x86_64, linux aarch64, macos}.
```

Dependency rule: consumers (`kino_loge`, `loge_mcp`, agents) and language packages depend
only on `loge`. Language packages never depend on each other or on `kino_loge`.

Intra-repo deps: `{:loge, path: "../loge"}` in development; switched to `{:loge, "~> x.y"}`
for publishing via an env flag (`LOGE_HEX=1`). Per-package git tags `loge_tptp-v0.1.0`;
`source_url_pattern` points at the package subdirectory.

## 3. Core contracts (`loge`)

### `Loge.Language` (behaviour)

```elixir
@callback id() :: atom()                       # :tptp, :asp, ...
@callback label() :: String.t()
@callback extensions() :: [String.t()]         # [".p", ".ax"]
@callback editor_language() :: String.t() | nil  # name passed to Livebook's editor (e.g. "tptp")
@callback analyze(binary(), keyword()) :: Loge.Analysis.t()
@callback format(binary(), keyword()) :: {:ok, binary()} | {:error, term()}   # optional
```

`Loge.Analysis`: `%{language: atom, source: binary, diagnostics: [Loge.Diagnostic.t],
native: term}`. `native` is the language package's own analysis (`Tptp.Analysis` for TPTP);
only that package's analyzers read it. Symbols and dialect live there, not in core.

### `Loge.Analyzer` (behaviour; generalises `Tptp.Analyzer`)

```elixir
@callback id() :: atom()
@callback label() :: String.t()
@callback languages() :: :any | [atom()]
@callback analyze(Loge.Analysis.t(), keyword()) :: [Loge.Diagnostic.t()]
```

`Loge.Analyzer.run_all/3` dispatches to the analyzers whose `languages/0` admit
`analysis.language` and returns `[{id, [Loge.Diagnostic.t] | :skipped}]`; per-analyzer
options sit under the analyzer's `id/0`. Raises, exits and throws become one `:error`
diagnostic `LOGE0001` on line 1 naming the analyzer (as `Tptp.Analyzer.run_all/3`).

### `Loge.Engine` (behaviour; generalises `AtpClient.Backend`)

```elixir
@callback id() :: atom()                       # :sotptp, :clingo, ...; unique among registered engines
@callback label() :: String.t()
@callback languages() :: [atom()]              # language ids it accepts
@callback config_schema() :: [Loge.Config.Field.t()]   # cross-cutting settings (credentials, binaries)
@callback configure(keyword()) :: :ok                  # makes settings the engine's for later runs
@callback verify(keyword()) :: :ok | {:error, term()}  # reachability probe
@callback controls() :: [Loge.Control.t()]    # per-run controls rendered by the cell
@callback run(Loge.Input.t(), keyword()) :: {:ok, Loge.Outcome.t()} | {:error, term()}
@callback format_error(term()) :: String.t()  # sentence for a reason run/verify returned
```

`Loge.configure!/2` checks the keys against `config_schema/0` and calls `configure/1`; the
TPTP engines merge the settings into `:atp_client`'s application environment under the
backend's `config_key/0`. `Loge.run!/3` calls `run/2` and returns the outcome or raises `Loge.Error`, whose message
is the engine's `format_error/1`. `Loge.Engine.to_source(engine, source, options, includes)`
renders `Loge.run!(Engine, "source", key: value, includes: %{"defs" => defs})`, the one call
the cell evaluates; it is the same for every engine, so it is a core function, not a
callback. `includes` are binding variables, referenced by name.

Cancellation contract (copied from AtpClient): death of the process calling `run/2`
aborts the work and releases external resources.

`Loge.Config.Field`: `%{key, type: :string | :integer | :boolean | :string_list, required?,
group, default, label, doc, secret?}` (same shape as `AtpClient.Config.Field`).

`Loge.Control`: `%{key, type: :select | :text | :integer | :boolean, label, choices:
[term] | {:dynamic, (-> [term])}, default}`. For `:text`, choices are suggestions. A
control's value reaches `run/2` under `key`; TPTP engines use the `atp_client` option
names as keys, so values pass through unchanged.

### `Loge.Input` (protocol)

```elixir
@spec to_iodata(t) :: iodata
@spec language(t) :: atom() | nil
```

Implemented for `BitString` (language `nil`) and `Loge.Source` in core; `Tptp.File`/`Tptp.Unit`
in `loge_tptp`; `Egglog.Commands` in `loge_egglog`.

### Includes

A source can include sources other cells define. `Loge.source(:tptp, text)` builds a
`Loge.Source`; a cell bound to a variable evaluates to one. `c:Loge.Language.analyze/2` and
`c:Loge.Engine.run/2` accept `includes: %{name => Loge.Input.t()}`
(`t:Loge.Language.includes/0`); an include names a source by the exact variable name.
Each language package resolves its own include syntax against the map. TPTP:
`Tptp.Resolver.Map` over the includes, then `:library` (default `Tptp.Resolver.Http`, which
fetches from tptp.org and caches on disk). Findings inside an include are placed on the root
directive that reaches it, prefixed `in '<name>': `. Engines receive the problem with every
include inlined (a `Tptp.Unit`) when includes are given, the source as written otherwise; an
unresolved include is `{:error, {:unresolved_includes, diagnostics}}`.

### `Loge.Diagnostic` (struct; fields of `Tptp.Diagnostic`, `range` for `span`)

`%{code: binary, severity: :error | :warning | :info | :hint, range: Loge.Range.t,
message: binary, hint: binary | nil, related: [{Loge.Range.t, binary}]}`.

### `Loge.Range` (struct)

`%{line, column, end_line, end_column}`, exactly the position keys of Kino's smart-cell
diagnostics (kino#522, livebook#3235): `line` 1-based and required; `column` 1-based in
UTF-16 code units, `nil` = first non-whitespace character; `end_line` `nil` = `line`;
`end_column` exclusive, `nil` = end of line without trailing whitespace. Each language
package converts its tool's convention once; `Loge.Range.from_offsets/3` does it for
byte offsets (tptp, Elixir lexers). The cell passes ranges through unchanged, renaming
`message` to `description`.

### `Loge.Outcome` (struct)

`%{szs: Tptp.Szs.Ontology.t() | nil, raw: binary, engine: atom, views: [view], details: map}`

`szs` is set where the SZS ontology describes the result exactly: an ATP verdict,
SAT/UNSAT, a timeout. A Prolog answer (`true`/`false`) or an egglog run
(`completed`/`check failed`) has `szs: nil` and a `{:badge, label, tone}` view; the cell
shows the SZS verdict only when there is one.

`view` is a closed set the frontend knows how to render:
`{:text, binary, lang_id | nil}`, `{:badge, label, tone}`, `{:table, columns, rows}`,
`{:models, [...]}`, `{:graph, dot}`, `{:diagnostics, [Loge.Diagnostic.t]}`.
Adding a view kind is a core change; adding an engine is not.

### `Loge.Registry`

Sources, in order: `config :loge, languages: [...], engines: [...], analyzers: [...]`
(read once in `Loge.Application.start/2`) and runtime `Loge.register/1` called from each
package's `Application.start/2` (works under `Mix.install`). Stored in `:persistent_term`;
no process. A module's kind is read from its `@behaviour`; anything else is
`{:error, {:not_a_loge_module, module}}`. Guards with `Code.ensure_loaded?/1`.
API: `languages/0`, `engines/0`, `engines_for(language_id)`, `analyzers_for(language_id)`,
`language_for_extension/1`.

### `Loge.Run`

A `Task.Supervisor`; every `run/2` and every lint executes under
`Loge.Run.async/1`, which wraps `Task.Supervisor.async_nolink`. Callers receive
`{ref, result}` or `:DOWN` as with any `async_nolink`. Never `Task.async` from a cell
process (a linked task exit kills the editor).

An `async_nolink` task outlives its caller, so the supervised task monitors the caller
and runs the work in a linked child; on the caller's `:DOWN` it exits, which kills the
work and so honours the engine cancellation contract.

Work outside the BEAM's reach needs more, and core provides three pieces:

- `Loge.Executable.run(executable, arguments, input, options)`: runs a command-line
  tool on its input written to a temporary file, under a `/bin/sh` wrapper that
  SIGKILLs the tool and removes the file when the Port's pipe closes or receives a
  line. The pipe closes when the caller dies and when the node halts or crashes, so no
  tool outlives either; a line is how `:timeout` stops it, keeping the output so far.
  stderr is merged or discarded (the wrapper's own `Killed` notices are discarded).
  Used by `loge_asp` (clingo) and `loge_smtlib` (z3, cvc5); the template for further
  Port engines (kissat, CaDiCaL, Vampire).
- `Loge.Guard.start(release)`: a process monitoring its starter that calls `release`
  when the starter dies, unless dismissed. Used to kill a process holding a Port
  (`loge_prolog`'s SWI session, whose `swipl` exits when its stdin closes).
- `Loge.Peer.call(m, f, a)`: applies `m.f(a)` in a fresh `:peer` node (`standard_io`
  connection, this node's code path, about 130 ms to start), stopped by a guard when the
  caller dies. For NIFs on dirty schedulers, which nothing in the BEAM can interrupt
  (`loge_egglog`). Arguments and results are copied; NIF resources cannot cross.

## 4. Data flow in the cell (`kino_loge`)

```
bind  → scan_binding/3 → every bound Loge.Input with a language, as Loge.Source
      → the cell keeps those of its language, for linting only
edit  → handle_editor_change/2 → debounced (300 ms) Loge.lint/3 under Loge.Run
      → diagnostics in Kino's editor format, listed under the editor; inline once
        reconfigure_smart_cell(editor: [diagnostics:]) ships (livebook#3235 / kino#522)
eval  → KinoLoge.Setup.to_source/1 → Loge.run!(..., includes: %{"defs" => defs}), or
        `defs = Loge.source(:lang, "...")` for a definitions cell → Outcome
      → Kino.Render (KinoLoge.Outcome): Result tab (verdict: name, mnemonic, description in
        the tone's colour, SZS link; then the views), Output tab (raw output)
```

Only `to_attrs/1` output is persisted (base64 JSON in the `.livemd`). The generated source
must run without `kino_loge`: one engine call with named options, no helper modules.

The generated source is a function of the attrs alone. Includes come from the source text
(`c:Loge.Language.include_names/1`), not from the binding: `scan_binding/3` runs
asynchronously after the parents evaluate (Livebook `runtime_server.ex`,
`scan_binding_after_evaluation/2`), so source derived from it could lag the evaluation.
Each include name that `Loge.Variable.parse/1` accepts becomes a variable reference; a
missing one is Elixir's "undefined variable". Ids, control keys and select choices in attrs
are matched by their string form (`KinoLoge.Setup`); no atom is made from them.

Cells:

- `KinoLoge.Cell` ("Logic Engine"): language select → engine select (`engines_for/1`, or
  none for a definitions cell with a variable) → controls from `controls/0` → managed editor
  (`editor: [source:, language: Language.editor_language()]`) → diagnostics list. Kino cannot
  reconfigure the editor language, so a language change is highlighted after the cell
  restarts.
- `KinoLoge.ConfigCell` ("Logic Engine Settings"): form generated from every registered
  engine's `config_schema/0`, one engine shown at a time, grouped by field group
  (`:advanced` collapsed), with a per-engine probe (`verify/1` under `Loge.Run`). Its
  source is one `Loge.configure!/2` call per engine with values. A `secret?` field holds
  a Livebook secret name, typed or chosen with Livebook's picker (`ctx.selectSecret`); the
  source reads
  `System.fetch_env!("LB_<name>")`, as Livebook exposes secrets to the runtime
  (`session.ex`, `set_runtime_secrets/2`), so no secret is written into the notebook.
  Generalises `KinoAtpClient.BackendConfig`, without its directory browser.

Robustness: `handle_event/3` must be total (no `String.to_existing_atom/1` on untrusted
keys); persist the source attr on every change; supervised unlinked tasks only.

## 5. State across runs

There are no engine sessions: every run starts from its input alone, as notebook
re-evaluation needs. A fresh `swipl` per Prolog run starts in about 60 ms, and
`Egglog.Program.run/3` clones its base per run; an `Egglog.EGraph` carried across cells
would make a cell's result depend on how often earlier cells ran. The generated source
also has no owner to key a session on: it runs in Livebook's evaluator, not the cell.

What is shared is node-wide and supervised by its language package. `loge_tptp` has
`Loge.Tptp.IsabelleServer`, the local Isabelle server `Loge.Tptp.Engines.Isabelle`
uses when no password is configured (generalising KinoAtpClient's `IsabelleRuntime`):

- started on the first run or verify, with `isabelle` from `ISABELLE_TOOL` or `PATH`
  (`IsabelleClient.start_server/1`, about 1 s); nothing runs before;
- every run opens its own HOL session on it through `AtpClient.Isabelle.query/2`
  (about 2.5 s; `IsabelleRuntime` kept one session, but a cancelled run closes its
  session, so a shared one would end every concurrent run with it);
- killed with the node however it ends: a `/bin/sh` watchdog reading from a Port of
  the server process runs `isabelle server -n <name> -x` when the pipe closes. Without
  it, a node that exits without `terminate/2` (`mix test`, `System.halt/0`, a stopped
  Livebook runtime) leaves the server running (observed). The server inherits the
  node's stderr.

## 6. Verified facts per backend (diagnostics)

All read from source, not executed. Links in §8.

| Tool                 | Positions come from                                                                                                                                               | Message shape                                                                        | Line/col base                        | Count                                                             | Severities                                                                        |
| -------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------ | ------------------------------------ | ----------------------------------------------------------------- | --------------------------------------------------------------------------------- |
| tptp                 | `Tptp.Diagnostic` byte spans                                                                                                                                      | structured                                                                           | offsets                              | all                                                               | error/warning/info/hint                                                           |
| clingo 5.8.2 (executed) | stderr of the bundled `clingo` executable (`--outf=3 --solve-limit=0`), the same text the `logger:` callback receives; the file is the one clingo read | `<file>:L:C-[L2:]C2: error\|warning\|info: msg`, body lines indented by two spaces, then `note:` lines with their own positions; a closing `*** ERROR: (clingo): …` summary | 1/1, bytes, end exclusive | all, capped by `message_limit` | error, warning, info; a grounding error stops before the infos of the rest |
| egglog (rev b912caa, egglog_elixir 45e8e55, executed) | `Egglog.parse/1` → `{:error, {:invalid_theory, msg, location}}`, `location` with `start_byte`/`end_byte` (end exclusive) and 1-based line/column; type and unbound-name errors only at run time, `{:error, {:native_error, msg}}` without location | `In L:C-C2: <quote>\nparse error: msg`; run errors `In …\nmsg`; failed check `{:error, {:check_failed, msg}}` | bytes, from the NIF | first only | error |
| SWI-Prolog 10.0.1 (executed) | `read_term/3` on a UTF-8 file stream with `subterm_positions`, `singletons`; `error(syntax_error(M), stream(S, Line, LinePos, CharNo))` | `message_to_string/2` of the error | character offsets (`char_count`), 0-based | all: after a syntax error `read_term/3` resumes after the next full stop | error; singletons as warnings positioned on the variable |
| z3 5.3.3 (executed) | stdout; continues after an error | `(error "line L column C: msg")`; responses in command order; `echo` text unquoted | 1/0 (bytes assumed) | every error | error; z3 accepts some ill-sorted terms cvc5 rejects (`(> x true)`) |
| cvc5 1.4.2 (executed) | stdout; warnings on stderr; stops at the first error | `(error "Parse Error: <file>:L.C: msg")`, or no position (`cannot push …` without `--incremental`); exit 1 | 1/1 | first | error |
| kissat / CaDiCaL     | stderr                                                                                                                                                            | `<name>:<line>: parse error: msg`, exit 1                                            | line only                            | first                                                             | error                                                                             |

Notes:

- ASP runs the `clingo` executable, not the NIF: libclingo cannot interrupt grounding, so a
  program whose grounding does not end (`p(X+1) :- p(X).`, easily typed mid-edit) is
  stopped only by killing its process. With the NIF, killing the session owner during
  grounding leaves the grounder running, and the VM segfaults when the session closes under
  it (observed with clingo_elixir 1b5d4ab). `Loge.Executable` runs it: the lint merges
  stderr (`--outf=3` writes nothing to stdout) with a 10 s deadline; the engine discards
  stderr, which can land inside a JSON line, and uses clingo's `--time-limit` so the
  JSON stays complete. On exit 65 the engine runs the lint for diagnostics. Exit codes
  are clasp's `ExitCode` bits (1 interrupted, 10 a model, 20 exhausted, 65 error).
- `Clingo.Dimacs.solve!/2` rewrites CNF as a choice-rule ASP program in Elixir; it does not
  call clasp's DIMACS reader, and raises `ArgumentError` on input it does not read; the
  engine sends only what `Loge.Dimacs.Cnf` accepts and renders. `picosat_elixir` and
  `simple_sat` accept clause lists only; `picosat_elixir` 0.2.3 solves on a normal
  scheduler without interrupt, so it cannot meet the cancellation contract.
- clingo_elixir's dispatcher monitors the process that opened the session and aborts the
  native search when it dies (`Clingo.Dispatcher.terminate/2`). Grounding is not aborted;
  for a CNF, whose translation grounds in time linear in its size, it ends late but ends.
- Prolog linting lives in Prolog, `loge_prolog/priv/loge.pl`, loaded into a fresh `swipl`:
  `read_term/3` over the program file in a temporary module, executing `op/3` directives;
  singletons located by walking `subterm_positions`; `_`-prefixed names skipped. The
  bridge runs each query in a Prolog engine whose stream aliases are its own: output is
  captured by redirecting in the worker thread (a loaded directive) and again in each
  `solve/2`. `SWI.query/3` raises on timeouts and Prolog errors; `Loge.Prolog.Swipl`
  rescues `SWI.Error` once per answer pull to keep earlier answers.
- SMT-LIB lint cannot come from the solvers (first error, full run, and they disagree on
  what is well-sorted): `Loge.Smtlib.Sexp` reads S-expressions with byte spans, and
  `Loge.Smtlib.Commands` checks command names, arity and the kinds of name positions
  (SMT-LIB 2.6 §4.1), only once the script reads. Solver errors become diagnostics in
  the outcome, not a failed run. Both solvers flush each response through a pipe, so a
  run killed at its deadline keeps its earlier answers; their own limits are not used
  (z3 `-T` and cvc5 `--tlimit-per` only answer `unknown`; cvc5 `--tlimit` aborts with
  a core dump).
- egglog: `EGraph::parse_program` is separate from `run_program`; the NIF calls it with
  filename `None`. Runs are not interruptible: a run whose caller died kept a core busy
  (measured); egglog's own early stop is only triggered from primitives. Hence
  `Loge.Peer`.

## 7. Editor facts (Kino 0.19.1, Livebook main @ ef1b666)

- Managed editor: `init/2` returns `{:ok, ctx, editor: [source:, language:, placement:,
visible:]}`; `handle_editor_change/2` required. `language` is matched by name against a
  fixed list (elixir, erlang, sql, python, yaml, json, xml, css, html, javascript,
  dockerfile, shell, toml, markdown); an unknown name is plain text, no error.
  livebook#3234 (open) adds `LanguageDescription.of({name: "TPTP"})`; its description
  uses `language: "tptp"`. Case-insensitive matching is not verified.
- Released Kino: `reconfigure_smart_cell/2` accepts only `editor: [:source,
  :intellisense_node, :visible]` (validated in `Kino.SmartCell.Server.reconfigure_smart_cell/2`).
  kino#522 (open) adds `:diagnostics`; livebook#3235 (open) carries it in
  `{:runtime_smart_cell_editor_update, ref, %{diagnostics: [code_marker]}}` to
  `setCodeMarkers` under the `secondary` tag, without validation.
- Diagnostic keys (kino#522 docs): `:line` (1-based, required), `:column` (1-based,
  default first non-whitespace character), `:end_line` (default `:line`), `:end_column`
  (exclusive, default end of `:end_line` without trailing whitespace), `:severity`
  (`:error | :warning | :info | :hint`, required), `:description` (required). Columns count
  UTF-16 code units. Each update replaces all diagnostics; `[]` clears. Not persisted: send
  again in `handle_connect/1`.
- Livebook's JS drops markers whose line is outside the document, clamps columns to the
  line, and treats column `0` as absent.
- Persistence: for both editor kinds only the attrs Kino reports are stored; on crash the
  cell shows "Restart Smart cell" and `init/2` receives the last reported attrs.

## 8. Sources

Own repos: [KinoAtpClient](https://github.com/jcschuster/KinoAtpClient),
[AtpClient](https://github.com/jcschuster/AtpClient), [tptp](https://github.com/jcschuster/tptp),
[lang-tptp](https://github.com/jcschuster/lang-tptp).
Wrapped libraries: [clingo_elixir](https://github.com/davfuenmayor/clingo_elixir),
[egglog_elixir](https://github.com/davfuenmayor/egglog_elixir),
[swi_elixir](https://github.com/davfuenmayor/swi_elixir).
Livebook/Kino: [livebook#3234](https://github.com/livebook-dev/livebook/pull/3234),
[livebook#3235](https://github.com/livebook-dev/livebook/pull/3235),
[kino#522](https://github.com/livebook-dev/kino/pull/522),
[smart_cell.ex](https://github.com/livebook-dev/kino/blob/main/lib/kino/smart_cell.ex),
[smart_cell/server.ex](https://github.com/livebook-dev/kino/blob/main/lib/kino/smart_cell/server.ex),
[languages.js](https://github.com/livebook-dev/livebook/blob/main/assets/js/hooks/cell_editor/live_editor/codemirror/languages.js),
[live_editor.js](https://github.com/livebook-dev/livebook/blob/main/assets/js/hooks/cell_editor/live_editor.js),
[session.ex](https://github.com/livebook-dev/livebook/blob/main/lib/livebook/session.ex),
[session/data.ex](https://github.com/livebook-dev/livebook/blob/main/lib/livebook/session/data.ex).
Upstream tools: [clingo locatable.hh](https://github.com/potassco/clingo/blob/v5.8.2/libgringo/gringo/locatable.hh),
[nongroundparser.cc](https://github.com/potassco/clingo/blob/v5.8.2/libgringo/src/input/nongroundparser.cc),
[clingo.h](https://github.com/potassco/clingo/blob/v5.8.2/libclingo/clingo.h);
[egglog parse.rs](https://github.com/egraphs-good/egglog/blob/b912caa9694c0c029f9ae3d91db0adc8824e14f5/src/ast/parse.rs),
[span.rs](https://github.com/egraphs-good/egglog/blob/b912caa9694c0c029f9ae3d91db0adc8824e14f5/egglog-ast/src/span.rs);
[SWI pl-read.c](https://github.com/SWI-Prolog/swipl-devel/blob/V10.0.1/src/pl-read.c),
[read_term/2](https://www.swi-prolog.org/pldoc/man?predicate=read_term/2),
[read_clause/3](https://www.swi-prolog.org/pldoc/man?predicate=read_clause/3),
[open_string/2](https://www.swi-prolog.org/pldoc/man?predicate=open_string/2);
[z3 smt2parser.cpp](https://github.com/Z3Prover/z3/blob/master/src/parsers/smt2/smt2parser.cpp);
[cvc5 lexer.cpp](https://github.com/cvc5/cvc5/blob/main/src/parser/lexer.cpp),
[cvc5_parser.cpp](https://github.com/cvc5/cvc5/blob/main/src/api/cpp/cvc5_parser.cpp);
[kissat application.c](https://github.com/arminbiere/kissat/blob/master/src/application.c);
[cadical parse.cpp](https://github.com/arminbiere/cadical/blob/master/src/parse.cpp).
Registries: [codemirror-lang-tptp](https://registry.npmjs.org/codemirror-lang-tptp),
[@codemirror/legacy-modes](https://registry.npmjs.org/@codemirror%2Flegacy-modes),
[codemirror-lang-prolog](https://registry.npmjs.org/codemirror-lang-prolog),
[zee3](https://hex.pm/packages/zee3), [picosat_elixir](https://hex.pm/packages/picosat_elixir).
