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
| Verdicts          | Every `Loge.Outcome` carries an SZS status (`Tptp.Szs.Ontology.t()`).                                                                          |
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
  loge_dimacs/  (phase 2)   Deps: loge, clingo_elixir and/or picosat_elixir.
  loge_asp/     (phase 2)   Deps: loge, clingo_elixir.
  loge_prolog/  (phase 3)   Deps: loge, swi_elixir.
  loge_egglog/  (phase 3)   Deps: loge, egglog_elixir.
  loge_smtlib/  (phase 4)   Deps: loge only; z3/cvc5 via Port.
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
@callback id() :: atom()                       # :sotptp, :clingo, ...
@callback label() :: String.t()
@callback languages() :: [atom()]              # language ids it accepts
@callback config_schema() :: [Loge.Config.Field.t()]   # cross-cutting settings (credentials, binaries)
@callback configure(keyword()) :: :ok                  # makes settings the engine's for later runs
@callback verify(keyword()) :: :ok | {:error, term()}  # reachability probe
@callback controls() :: [Loge.Control.t()]    # per-run controls rendered by the cell
@callback run(Loge.Input.t(), keyword()) :: {:ok, Loge.Outcome.t()} | {:error, term()}
@callback format_error(term()) :: String.t()  # sentence for a reason run/verify returned
@callback session() :: module() | nil          # optional; phase 3, see §5
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

`%{szs: Tptp.Szs.Ontology.t(), raw: binary, engine: atom, views: [view], details: map}`

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
  engine's `config_schema/0`, grouped by field group, with a per-engine probe (`verify/1`
  under `Loge.Run`). Its source is one `Loge.configure!/2` call per engine with values.
  A `secret?` field holds a Livebook secret name; the source reads
  `System.fetch_env!("LB_<name>")`, as Livebook exposes secrets to the runtime
  (`session.ex`, `set_runtime_secrets/2`), so no secret is written into the notebook.
  Generalises `KinoAtpClient.BackendConfig`, without its directory browser.

Robustness: `handle_event/3` must be total (no `String.to_existing_atom/1` on untrusted
keys); persist the source attr on every change; supervised unlinked tasks only.

## 5. Sessions (phase 3)

Stateless engines (AtpClient, `Clingo.solve!`, `Egglog.Program`) need nothing. Stateful
ones (`SWI` session, `Egglog.EGraph`, a local Isabelle server) declare `session/0`; `Loge.SessionSupervisor`
starts one process per owner (cell id / MCP connection), passes it as `opts[:session]` to
`run/2`, and tears it down when the owner dies.

Until then `Loge.Tptp.Engines.Isabelle` runs `AtpClient.Isabelle.query/2` against a
configured server; KinoAtpClient's node-wide `IsabelleRuntime` (local server started on
demand when `isabelle` is on PATH) is not ported and becomes this engine's session.

## 6. Verified facts per backend (diagnostics)

All read from source, not executed. Links in §8.

| Tool                 | Positions come from                                                                                                                                               | Message shape                                                                        | Line/col base                        | Count                                                             | Severities                                                                        |
| -------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------ | ------------------------------------ | ----------------------------------------------------------------- | --------------------------------------------------------------------------------- |
| tptp                 | `Tptp.Diagnostic` byte spans                                                                                                                                      | structured                                                                           | offsets                              | all                                                               | error/warning/info/hint                                                           |
| clingo 5.8.2         | logger callback (`logger:` option on `Clingo.solve!`/`Control.new!`); API-added programs are file `<block>`                                                       | `<block>:L:C[-C2 \| -L2:C2]: error\|warning\|info: msg` (multi-line bodies possible) | 1/1                                  | all, capped by `message_limit` (clingo_elixir passes 20)          | error, warning, info                                                              |
| egglog (rev b912caa) | `Egglog.parse/1` → `{:error, {:invalid_theory, msg}}`; run errors `{:error, {:native_error, msg}}`                                                                | `In L:C-C2: <quote>\nparse error: msg` or `In L:C-L2:C2: …`; type errors `In …\nmsg` | 1/1, char-counted, end inclusive     | first only                                                        | error                                                                             |
| SWI-Prolog 10.0.1    | `error(syntax_error(Culprit), Loc)`; `Loc` ∈ `file(F,Line,LinePos,CharNo)`, `stream(S,Line,LinePos,CharNo)` (incl. `open_string/2` streams), `string(Str,CharNo)` | term; the bridge serialises with `term_string/3`                                     | 1-based line, 0-based linepos/charno | all via a `read_term/3` loop; swi_elixir's `load` keeps the first | error; `singletons(Term,Names)` / `discontiguous/2` as warnings without positions |
| z3                   | stdout                                                                                                                                                            | `(error "line L column C: msg")`, exit 1                                             | 1/0                                  | first per command                                                 | error                                                                             |
| cvc5                 | stdout                                                                                                                                                            | `(error "Parse Error: <stdin>:L.C: msg")`, exit 1                                    | 1/0                                  | first                                                             | error                                                                             |
| kissat / CaDiCaL     | stderr                                                                                                                                                            | `<name>:<line>: parse error: msg`, exit 1                                            | line only                            | first                                                             | error                                                                             |

Notes:

- ASP lint needs `Control.new!(logger:)` + `add!` + `ground!`; grounding surfaces undefined
  atoms and unsafe variables. `Clingo.Ast.parse!/2` passes `nil` as logger (positions lost).
- `Clingo.Dimacs.solve!/2` rewrites CNF as a choice-rule ASP program in Elixir; it does not
  call clasp's DIMACS reader. `picosat_elixir` and `simple_sat` accept clause lists only.
- Prolog linting lives in Prolog: `open_string/2` + `read_term/3` with `syntax_errors(dec10)`
  under a local `message_hook`, `singletons(warning)`, `term_position`, `subterm_positions`,
  `variable_names`, `comments`, `module(M)`; run through `SWI.query`. No swi_elixir change needed.
- SMT-LIB lint cannot come from the solvers (first error, full run); write an S-expression
  lexer + command-level lint in Elixir.
- egglog: `EGraph::parse_program` is separate from `run_program`; the NIF calls it with
  filename `None`.

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
