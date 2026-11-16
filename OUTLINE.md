# Loge — Design Outline

Loge ("Logic Engines") is a set of Elixir libraries that give logic engines one
interface: sources in, an outcome out. An engine solves a source, checks one, or
translates it into another language under a stated semantic relation. The Livebook smart
cells of `kino_loge` are the first consumer of that interface and Elixir code is the
second; an MCP server is a later one (§10). Loge succeeds
[KinoAtpClient](https://github.com/jcschuster/KinoAtpClient).

This file is the design reference. `PLAN.md` holds the phased execution plan.

## 0. Scope

Declarative representations, the engines that answer questions about them, and the
translations between them that preserve a stated semantic relation.

| Term     | Meaning                                                                                                                             |
| -------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| Source   | Text in a language; a value a notebook binds to a name (`Loge.Source`).                                                             |
| Language | How a source is read, linted and highlighted (`Loge.Language`).                                                                     |
| Engine   | Performs one task on sources (`Loge.Engine`).                                                                                       |
| Outcome  | What a run returns: a status (`Loge.Status`), views, and possibly a source as output (`Loge.Outcome`).                              |
| Role     | A source an engine needs beside its input and that the input's language cannot name (`Loge.Role`).                                  |

An engine belongs in Loge when it passes both tests:

- Semantic: its answer is fixed by the declarative semantics of its input. The three
  tasks are `solve` (satisfiability, entailment, models, answers to a query), `check`
  (whether a given structure or derivation is what it claims to be) and `translate`
  (a source in another language, with the relation between the two stated).
- Architectural: a run is a stateless, cancellable function from sources to an outcome
  (§5).

Out of scope:

- Interactive provers: they hold state across steps. Isabelle documents are
  `kino_isabelle`'s; Loge uses Isabelle only as a prover for TPTP problems.
- Algorithms as teaching material, such as a DPLL trace. Loge has solvers.
- A Datalog language. egglog covers Datalog.
- Conversion between syntaxes of one language, visualisation and data generation as
  tasks of their own. A language package exposes the reasoning tasks, not the whole
  toolbox of the library it wraps.
- Natural language to formal source. That is the caller's work, an agent's for instance.
- General-purpose databases and SQL.

The scope is sized to the logic representation course and to agent experiments across
representations ("if this can be a satisfiability problem, translate it and solve it"):

| Course topic                                            | Languages and tasks                                                                   | State                                    |
| ------------------------------------------------------- | ------------------------------------------------------------------------------------- | ---------------------------------------- |
| Propositional logic, SAT                                | DIMACS and SAT solving; TPTP to CNF to DIMACS                                         | DIMACS with clasp; translations phase 8  |
| Predicate logic, Horn logic, Datalog, logic programming | TPTP provers, Prolog, egglog; clausification, grounding                               | engines exist; translations phase 8      |
| Modal and description logics, correspondences           | non-classical TPTP; embedding into THF; translations between DL, modal logic and FOL  | phase 9                                  |
| TPTP infrastructure                                     | provers, verifiers (GDV, AGMV), problem tools                                         | provers and verifiers exist              |
| Semantic web                                            | RDF (Turtle), SPARQL, SHACL, ShEx                                                     | `loge_turtle`, `loge_sparql`, `loge_shex` exist |

## 1. Decisions (fixed)

| Decision          | Choice                                                                                                                                         |
| ----------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| Editor            | CodeMirror 6 bundled with `kino_loge`, edited collaboratively through the cell process (§7). Not Livebook's managed smart-cell editor.         |
| Highlighting      | Lezer grammars, one npm package per language, imported by the editor bundle and chosen by `editor_language/0`. No JS in language packages.     |
| Positions         | Diagnostics carry line/column ranges in Kino's smart-cell diagnostics format (kino#522): 1-based, columns in UTF-16 code units.                |
| Linting / solving | Extensible from Elixir through behaviours; each language is its own Hex package.                                                               |
| Tasks             | An engine declares one: `:solve`, `:check` or `{:translate, to, preserves}` (§3). Cells and consumers treat the three alike.                   |
| Verdicts          | Every `Loge.Outcome` carries a status of `Loge.Status`: a value of the SZS ontology where it describes the result, one of Loge's own otherwise (§3). A translation's status is the relation it preserves between input and output. |
| Sources in a run  | A question the language has syntax for is part of the source (a conjecture, `(check-sat)`, `?- Goal.`). A reference the language can express is an include. A source the language cannot name is a role (§3). No control carries part of a problem. |
| Translations      | Written in Elixir, in the package of the source language; verified before publication, not in CI (§8, §9).                                     |
| Cells             | Two, by what they produce: a Source cell binds a source, an Engine cell binds an outcome (§4). None per task.                                  |
| Solve             | Livebook's own cell evaluation (Kino has no API for a cell to evaluate itself). Raw output is the outcome's Output tab.                          |
| Input             | `Loge.Input` protocol (mirrors `AtpClient.Input`). An outcome is an input: its output.                                                         |
| Minimum Elixir    | `~> 1.20`.                                                                                                                                     |
| Naming            | Hex package name = module namespace: `loge` → `Loge`, `loge_tptp` → `Loge.Tptp`, `kino_loge` → `KinoLoge`.                                     |
| Repo              | Monorepo, one mix project per directory, no umbrella (Nx pattern).                                                                             |

## 2. Repository layout

```
loge/                       this repo
  OUTLINE.md  PLAN.md  README.md  .formatter.exs  .gitignore
  loge/                     core: behaviours, registry, structs, run supervision. Deps: tptp (SZS ontology).
  loge_tptp/                Language + analyzers + engines for TPTP: provers, verifiers,
                            translations. Deps: loge, tptp, atp_client.
  kino_loge/                Smart cells and Kino.Render. Deps: loge, kino.
  loge_dimacs/  (phase 2)   Deps: loge, clingo_elixir.
  loge_asp/     (phase 2)   Deps: loge, clingo_elixir.
  loge_prolog/  (phase 3)   Deps: loge, swi_elixir.
  loge_egglog/  (phase 3)   Deps: loge, egglog_elixir.
  loge_smtlib/  (phase 4)   Deps: loge only; z3/cvc5 executables via Loge.Executable.
  loge_turtle/  (phase 10)  Turtle; SHACL validation. Deps: loge, rudof_elixir.
  loge_sparql/  (phase 10)  SPARQL; queries on a graph and on an endpoint. Deps: loge, rudof_elixir.
  loge_shex/    (phase 10)  ShExC and ShapeMap; ShEx validation. Deps: loge, rudof_elixir.
  notebooks/                demo.livemd (guided tour of every package), and one smoke-test
                            notebook per language (pinned Mix.install).
  .github/workflows/ci.yml  matrix: package × {linux x86_64, linux aarch64, macos}.
```

Dependency rule: consumers (`kino_loge`, agents, later `loge_mcp`) and language packages
depend only on `loge`. Language packages never depend on each other or on `kino_loge`.
`loge_mcp` is not planned here; §10 says what the libraries hold ready for it.

Intra-repo deps: `{:loge, path: "../loge"}` in development; switched to `{:loge, "~> x.y"}`
for publishing via an env flag (`LOGE_HEX=1`). Per-package git tags `loge_tptp-v0.1.0`;
`source_url_pattern` points at the package subdirectory.

## 3. Core contracts (`loge`)

### `Loge.Language` (behaviour)

```elixir
@callback id() :: atom()                       # :tptp, :asp, ...
@callback label() :: String.t()
@callback extensions() :: [String.t()]         # [".p", ".ax"]
@callback editor_language() :: String.t() | nil  # name of its grammar in the cell's editor (e.g. "tptp")
@callback analyze(binary(), keyword()) :: Loge.Analysis.t()
@callback format(binary(), keyword()) :: {:ok, binary()} | {:error, term()}   # optional
```

`analyze/2` takes `includes:` (below) and `roles:`, the values of the roles of the
engine the source runs on, by role key (`t:Loge.Language.roles/0`), for a language whose
source cannot be read without them: a ShEx shape map names nodes by the data's prefixes
and shapes by the schema's. A language reads only the role keys of its own package's
engines. The Engine cell lints with the bound values of the roles it has set.

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
@callback task() :: task()                     # :solve | :check | {:translate, to, preserves}
@callback config_schema() :: [Loge.Config.Field.t()]   # cross-cutting settings (credentials, binaries)
@callback configure(keyword()) :: :ok                  # makes settings the engine's for later runs
@callback verify(keyword()) :: :ok | {:error, term()}  # reachability probe
@callback roles() :: [Loge.Role.t()]          # sources beside the input (below); [] for most
@callback controls() :: [Loge.Control.t()]    # per-run controls rendered by the cell
@callback run(Loge.Input.t(), keyword()) :: {:ok, Loge.Outcome.t()} | {:error, term()}
@callback format_error(term()) :: String.t()  # sentence for a reason run/verify returned
```

`Loge.configure!/2` checks the keys against `config_schema/0` and calls `configure/1`; the
TPTP engines merge the settings into `:atp_client`'s application environment under the
backend's `config_key/0`. `Loge.run!/3` calls `run/2` and returns the outcome or raises `Loge.Error`, whose message
is the engine's `format_error/1`. Before that it raises `ArgumentError` for an option
that is not a role key, a control key, a setting key or `:includes`, for a required
role that is missing, and for an input or a role's value whose `Loge.Input.language/1`
the engine or the role does not read: a misspelt option or a mismatched
pipeline fails with a sentence instead of running with defaults or failing in the tool's
words.

`task/0` is one of:

- `:solve`: the outcome answers the question the source states.
- `:check`: the input is a derivation or a structure, and the outcome says whether it is
  what it claims to be: `:verified_good` or `:verified_bad` where a verifier of the TPTP
  World gives it.
- `{:translate, to, preserves}`: the outcome's `output` is a source in the language
  `to`. `preserves` is the status relating the input, as Ax, to the output, as C:
  `:equivalent`, `:equi_satisfiable`, `:satisfiability_preserving`,
  `:unsatisfiability_preserving` or `:theorem` (§8). A successful run has
  `status: preserves`. An input outside the fragment the translation is defined on
  gives `status: :inappropriate`, a `{:diagnostics, …}` view naming what lies outside,
  and no output.

One engine module performs one task; a tool that does several is several engines.

`Loge.Engine.to_source(engine, input, options, references)` renders the one call a cell
evaluates; it is the same for every engine, so it is a core function, not a callback.
`input` is the source text, or an atom naming the variable that holds the input.
`references` are `roles: [key: variable]`, the variable that holds each role's value,
passed first; `includes: [name]`, the include names of the source, each passed as the
variable of that name; and `bind: variable`, the name the outcome is bound to, absent
for none:

    cnf = Loge.run!(Loge.Tptp.Engines.Clausify, "fof(a, axiom, p | q).", [])
    Loge.run!(Loge.Dimacs.Engines.Clasp, cnf, models: 1)
    Loge.run!(Engine, "include('defs').", time_limit: 10, includes: %{"defs" => defs})
    Loge.run!(Loge.Sparql.Engines.Query, "SELECT * {?s ?p ?o}", data: graph)

`Loge.Source.to_source/3` renders a Source cell's `Loge.source/3` call with the same
`includes:` and `bind:`.

Cancellation contract (copied from AtpClient): death of the process calling `run/2`
aborts the work and releases external resources.

`Loge.Config.Field`: `%{key, type: :string | :integer | :boolean | :string_list, required?,
group, default, label, doc, secret?}` (same shape as `AtpClient.Config.Field`).

`Loge.Control`: `%{key, type: :select | :text | :integer | :boolean, label, choices:
[term] | {:dynamic, (-> [term])}, default}`. For `:text`, choices are suggestions. A
control's value reaches `run/2` under `key`. Every engine names its time limit
`time_limit`, in seconds; the TPTP engines pass it on under the name their backend reads
(`time_limit_sec`, `cpu_timeout_s`) and their other controls under the `atp_client`
option names. `Loge.Control.cast/2` reads an external
value (a form field, a JSON value) as the control's type or returns `:error`; every
consumer reads control values through it. A control configures a run; it never carries
part of the problem.

### `Loge.Input` (protocol)

```elixir
@spec to_iodata(t) :: iodata
@spec language(t) :: atom() | nil
```

Implemented for `BitString` (language `nil`) and `Loge.Source` in core; `Tptp.File`/`Tptp.Unit`
in `loge_tptp`; `Egglog.Commands` in `loge_egglog`.

Also implemented for `Loge.Outcome`: as an input, an outcome is its `output`. One without
an output is its raw text and has no language, as a binary has none. The outcome of one
run is thereby the input of the next, in a notebook and in a pipeline alike.

### Questions

Where a language has syntax for the question, the question is part of the source: a TPTP
conjecture, SMT-LIB's `(check-sat)`, egglog's `(check …)`, a Prolog `?- Goal.`.
`Loge.Prolog.Engines.Swipl` consults the clauses and directives of its source and answers
each `?- Goal.` in it, in order, as the toplevel would.

### Includes

A source can include sources other cells define. `Loge.source(:tptp, text)` builds a
`Loge.Source`; a cell bound to a variable evaluates to one. `c:Loge.Language.analyze/2` and
`c:Loge.Engine.run/2` accept `includes: %{name => Loge.Input.t()}`
(`t:Loge.Language.includes/0`); an include names a source by the exact variable name.

A source carries the sources its own includes name,
`Loge.source(:tptp, text, includes: %{"defs" => defs})`, so it is closed: it can be
included or run from any cell without its includes being named again.
`Loge.Source.closure/2` collects by name the includes given to a run, then those its
input carries, then those each included source carries; a name keeps the first source
found, so a name given to a run shadows the same name inside an include. Each language
package resolves its own include syntax against the closure. TPTP:
`Tptp.Resolver.Map` over the includes, then `:library` (default `Tptp.Resolver.Http`, which
fetches from tptp.org and caches on disk). Findings inside an include are placed on the root
directive that reaches it, prefixed `in '<name>': `. Engines receive the problem with every
include inlined (a `Tptp.Unit`) when includes are given, the source as written otherwise; an
unresolved include is `{:error, {:unresolved_includes, diagnostics}}`.

Prolog, ASP and egglog include files, which their tools read themselves. A run writes
each source of the closure whose name is a word (letters, digits, underscores: the
names a cell can bind) as the file the tool looks for: `<name>.pl` beside the program
for SWI-Prolog's `:- [name].`, `include/1`, `consult/1` and `ensure_loaded/1`; `<name>`
beside it for clingo's `#include "name".` (`Loge.Executable`'s `:files`); `<name>` in
egglog's working directory, a directory of the run's, for `(include "name")`. Other
names are left to the tool. `include_names/1` reads the directives with a scanner of
the language's comments, strings and quoted atoms, without starting the tool. The ASP
lint grounds with the includes and names an included file in a finding on line 1;
the Prolog and egglog lints read the program alone.

### Roles (`Loge.Role`)

A role is a source an engine needs beside its input and that the input's language has no
syntax to name: the data graph of a SPARQL query or of SHACL shapes, the schema and the
data graph of a ShEx shape map. `c:Loge.Engine.roles/0` lists them as
`%Loge.Role{key, label, languages, required?}`. A role's value reaches `run/2` under
`key` as a `Loge.Input.t()`; role keys and control keys are disjoint. `Loge.run!/3` takes
role keys as options and raises `ArgumentError` for a required role that is missing and
for a value in a language the role does not list. A consumer offers the bound inputs of
the role's languages.

The editor holds what is asked and a role holds what it is asked of:

| Engine            | Editor                                       | Roles                                                                                         |
| ----------------- | -------------------------------------------- | --------------------------------------------------------------------------------------------- |
| SPARQL on a graph | the query                                    | `data` (Turtle)                                                                               |
| SHACL             | the shapes, with their targets               | `data` (Turtle), optional: without it the source is validated against the shapes it contains  |
| ShEx              | the shape map: which nodes, against which shapes | `schema` (ShExC) and `data` (Turtle)                                                      |

A ShEx schema is thereby a source many shape maps are asked of, as a Prolog program is of
many queries. A SPARQL query on an endpoint has no role: the endpoint is an address, given
by a control.

None of the languages of phases 1–4 has a role: TPTP, Prolog, ASP and egglog name other
sources through includes, and SMT-LIB and DIMACS sources are self-contained; their
engines return `[]`. Roles were built in phase 10, with fakes, before the engines of
the semantic web that need them.

### `Loge.Diagnostic` (struct; fields of `Tptp.Diagnostic`, `range` for `span`)

`%{code: binary, severity: :error | :warning | :info | :hint, range: Loge.Range.t,
message: binary, hint: binary | nil, related: [{Loge.Range.t, binary}]}`.

### `Loge.Range` (struct)

`%{line, column, end_line, end_column}`, exactly the position keys of Kino's smart-cell
diagnostics (kino#522, livebook#3235): `line` 1-based and required; `column` 1-based in
UTF-16 code units, `nil` = first non-whitespace character; `end_line` `nil` = `line`;
`end_column` exclusive, `nil` = end of line without trailing whitespace. Each language
package converts its tool's convention once; `Loge.Range.from_offsets/3` does it for
byte offsets (tptp, Elixir lexers), `Loge.Range.from_characters/3` for columns counted
in characters (rudof). The cell passes ranges through unchanged, renaming
`message` to `description`.

### `Loge.Outcome` (struct)

`%{status: Loge.Status.t(), problem: :entailment | :satisfiability | :translation | :verification, raw: binary, engine: atom, views: [view], output: Loge.Source.t() | nil, details: map}`

`output` is the source a run produced: a translation's target, a prover's derivation, a
model finder's interpretation, the graph of a SPARQL `CONSTRUCT`. A consumer shows it as
text in its language; an engine does not repeat it as a view.

`status` is a value of the SZS ontology where the ontology describes the result
exactly: an ATP verdict, SAT/UNSAT, a timeout. Otherwise it is one of Loge's own
(`Loge.Status`, below), such as `:yes` for a Prolog query with an answer.

`problem` is what the status is about. The SZS ontology defines its values over axioms
Ax and a conjecture C, so its descriptions fit `:entailment` (the default: TPTP, a Prolog
goal) and are not shown for `:satisfiability` (DIMACS, ASP, SMT-LIB), whose verdict is
name, mnemonic and SZS link. Loge does not reword the ontology's texts. What a status
does not say is a badge beside it: clingo's `OPTIMUM FOUND` is `:satisfiable` with an
`optimum found` badge. For `:translation` Ax is the input and C the output, and the
description is shown with that legend; for `:verification` the description
("The solution has been verified as good.") stands as it is. `VerifiedBad` is drawn in
the negative tone, though the ontology files it under Success: the verification
succeeded, the solution did not.

`view` is a closed set the frontend knows how to render:
`{:text, binary, editor_language | nil}` (highlighted by that grammar, or plain), `{:badge, label, tone}`, `{:table, columns, rows}`,
`{:models, [...]}`, `{:graph, mermaid}` (Mermaid flowchart source, drawn by `Kino.Mermaid`
without custom JS), `{:diagnostics, [Loge.Diagnostic.t]}`, `{:titled, title, view}`.
Adding a view kind is a core change; adding an engine is not.

### `Loge.Status`

Every outcome has a status, a `Loge.Status.t()`: a value of the SZS ontology, or one of
Loge's own for a verdict the ontology has no value for.

| Status           | States                                | Given by                                                    |
| ---------------- | ------------------------------------- | ----------------------------------------------------------- |
| `:yes`           | the question asked has an answer      | a Prolog query the toplevel answers `true`                  |
| `:no`            | it has none                           | a Prolog query answered `false`, a failed egglog `check`    |
| `:conformant`    | the data conforms to the shapes       | SHACL and ShEx validation (phase 10)                        |
| `:nonconformant` | it does not                           | SHACL and ShEx validation (phase 10)                        |

A run that asks nothing (a consulted Prolog program, an egglog run to its end, whose
checks are assertions that held, a SPARQL `CONSTRUCT`) or several things (an SMT-LIB
script with no `check-sat` or more than one) is SZS `:success`. No outcome has `nil`: a result none of the values states gets a value
here, not a badge. A badge remains for what stands beside a status, such as clingo's
`optimum found`.

`Loge.Status` gives each value its name, description and tone, and delegates to
`Tptp.Szs.Ontology` for the ontology's; `Loge.Verdict.of/2` reads them from it. Loge's
own values are answers, so they count as success; they have no mnemonic and no SZS
page. `:yes` and `:conformant` are drawn in the positive tone, `:no` in the neutral one,
as a goal that fails is no error, and `:nonconformant` in the negative one, as
`VerifiedBad` is. The `preserves` of a translation is a
`Loge.Status.t()` as well.

### `Loge.Registry`

Sources, in order: `config :loge, languages: [...], engines: [...], analyzers: [...]`
(read once in `Loge.Application.start/2`) and runtime `Loge.register/1` called from each
package's `Application.start/2` (works under `Mix.install`). Stored in `:persistent_term`;
no process. A module's kind is read from its `@behaviour`; anything else is
`{:error, {:not_a_loge_module, module}}`. Guards with `Code.ensure_loaded?/1`. An id is
unique within its kind: another module with an id its kind holds is
`{:error, {:duplicate_id, id, holder}}`.
API: `languages/0`, `engines/0`, `engines_for(language_id)`, `analyzers_for(language_id)`,
`language_for_extension/1`; `language/1` and `engine/1`, which find a module by its id
given as an atom or as the atom's string form, so that no consumer makes an atom from
external input; `translations/0`, which gives for each translate engine and each language
it accepts the engine with its source language, target language and relation: the edges
of the graph whose nodes are the languages.

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
  tool on its input written to a file in a temporary directory of its own, beside the
  `:files` it is given, under a `/bin/sh` wrapper that SIGKILLs the tool and removes
  the directory when the Port's pipe closes or receives a line. A file name is one path
  component, so no name written by a user reaches outside the directory. The pipe closes when the caller dies and when the node halts or crashes, so no
  tool outlives either; a line is how `:timeout` stops it, keeping the output so far.
  stderr is merged or discarded (the wrapper's own `Killed` notices are discarded).
  Used by `loge_asp` (clingo) and `loge_smtlib` (z3, cvc5); the template for further
  Port engines (kissat, CaDiCaL, Vampire).
- `Loge.Guard.start(release)`: a process monitoring its starter that calls `release`
  when the starter dies, unless dismissed. Used to kill a process holding a Port
  (`loge_prolog`'s SWI session, whose `swipl` exits when its stdin closes).
- `Loge.Peer.call(m, f, a, timeout: ms)`: applies `m.f(a)` in a fresh `:peer` node (`standard_io`
  connection, this node's code path, about 130 ms to start), stopped by a guard when the
  caller dies. For NIFs on dirty schedulers, which nothing in the BEAM can interrupt
  (`loge_egglog`, and the rudof engines and ShEx lints). Arguments and results are
  copied; NIF resources cannot cross. Its result is `{:ok, result}`; past the
  `:timeout` the peer is stopped and the call is `{:error, :timeout}`, which is how a
  time limit ends a run in a peer.

## 4. Data flow in the cells (`kino_loge`)

```
bind  → scan_binding/3 → every bound Loge.Input with a language, as Loge.Source
        (a source, whole with the sources it includes, or an outcome's output)
      → an Engine cell keeps those its engine accepts: to lint includes against, and as
        the choices for its input
edit  → "push" event (version, change sets) → KinoLoge.ChangeSet.apply/2 → "updates"
        broadcast to every client (§7) → debounced (300 ms) Loge.lint/3 under Loge.Run
      → diagnostics in Kino's editor format, drawn in the editor and listed under it
eval  → Source cell: `defs = Loge.source(:lang, "...")` → Loge.Source
      → Engine cell: `result = Loge.run!(Engine, input, ..., includes: %{"defs" => defs})`
        → Outcome
      → Kino.Render (KinoLoge.Outcome): Result tab (verdict: name, with the mnemonic
        where there is one, in the tone's colour; description unless the problem is one
        of satisfiability; SZS link for a value of the ontology; then the views; then the output as text in its language), Output tab (raw output as terminal
        text: monospace, at most 300 px high with scrolling, as Livebook draws stdout)
```

Cells are linked by variable names and by nothing else. Livebook marks a cell stale when
a variable it reads changes (since 0.8), so a run follows its sources without Loge
tracking anything. There is no cell per task: the task is the engine's, and the Engine
cell is the same for all three.

Only `to_attrs/1` output is persisted (base64 JSON in the `.livemd`). The generated source
must run without `kino_loge`: one engine call with named options, no helper modules.

The generated source is a function of the attrs alone. Includes come from the source text
(`c:Loge.Language.include_names/1`), not from the binding: `scan_binding/3` runs
asynchronously after the parents evaluate (Livebook `runtime_server.ex`,
`scan_binding_after_evaluation/2`), so source derived from it could lag the evaluation.
Each include name that `Loge.Variable.parse/1` accepts becomes a variable reference; a
missing one is Elixir's "undefined variable". The name of an input and the name of a
result are attrs in the same way: the binding supplies the choices, the attrs hold the
choice. Ids, control keys and select choices in attrs are matched by their string form
(`Loge.Registry.language/1`, `engine/1`, `Loge.Control.cast/2`); no atom is made from
them.

Cells:

- `KinoLoge.SourceCell` ("Logic Source"): language select → variable name (default from
  `Kino.SmartCell.prefixed_var_name/2`) → bundled editor → diagnostics list. Its source
  is `name = Loge.source(:lang, "…", includes: %{…})`, with the includes its text names.
  It produces a value and runs nothing, as kino_db's
  connection cell does beside its query cell.
- `KinoLoge.Cell` ("Logic Engine"): language select → engine select (`engines_for/1`,
  grouped by task) → input (this cell's editor, or a bound input the engine accepts,
  shown read-only in the editor; the select appears once there is a bound input to
  choose) → roles (one select per role, over the bound inputs of its languages, with
  `none` first; attr `"roles"`, reset when the engine changes) → controls from `controls/0` → result name (optional) →
  bundled editor (grammar `Language.editor_language()`, §7) → diagnostics list. Its
  source is one `Loge.run!/3` call, bound to the result name when there is one. A cell
  always has an engine.
- `KinoLoge.ConfigCell` ("Logic Engine Settings"): form generated from every registered
  engine's `config_schema/0`, one engine shown at a time, grouped by field group
  (`:advanced` collapsed), with a per-engine probe (`verify/1` under `Loge.Run`). Its
  source is one `Loge.configure!/2` call per engine with values. A `secret?` field holds
  a Livebook secret name, typed or chosen with Livebook's picker (`ctx.selectSecret`); the
  source reads
  `System.fetch_env!("LB_<name>")`, as Livebook exposes secrets to the runtime
  (`session.ex`, `set_runtime_secrets/2`), so no secret is written into the notebook.
  Generalises `KinoAtpClient.BackendConfig`, without its directory browser.

The collaborative source and the lint loop (§7) are one module, `KinoLoge.Editor`, which
both cells with an editor use.

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

All read from source, not executed. Links in §11.

| Tool                 | Positions come from                                                                                                                                               | Message shape                                                                        | Line/col base                        | Count                                                             | Severities                                                                        |
| -------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------ | ------------------------------------ | ----------------------------------------------------------------- | --------------------------------------------------------------------------------- |
| tptp                 | `Tptp.Diagnostic` byte spans                                                                                                                                      | structured                                                                           | offsets                              | all                                                               | error/warning/info/hint                                                           |
| clingo 5.8.2 (executed) | stderr of the bundled `clingo` executable (`--outf=3 --solve-limit=0`), the same text the `logger:` callback receives; the file is the one clingo read | `<file>:L:C-[L2:]C2: error\|warning\|info: msg`, body lines indented by two spaces, then `note:` lines with their own positions; a closing `*** ERROR: (clingo): …` summary | 1/1, bytes, end exclusive | all, capped by `message_limit` | error, warning, info; a grounding error stops before the infos of the rest |
| egglog (rev b912caa, egglog_elixir 0.2.0 at 901dc4a, executed) | `Egglog.parse/1` → `{:error, {:invalid_theory, msg, location}}`, `location` with `start_byte`/`end_byte` (end exclusive) and 1-based line/column; type and unbound-name errors only at run time, `{:error, {:native_error, msg}}` without location | `In L:C-C2: <quote>\nparse error: msg`; run errors `In …\nmsg`; failed check `{:error, {:check_failed, msg}}` | bytes, from the NIF | first only | error |
| SWI-Prolog 10.0.1 (executed) | `read_term/3` on a UTF-8 file stream with `subterm_positions`, `singletons`; `error(syntax_error(M), stream(S, Line, LinePos, CharNo))` | `message_to_string/2` of the error | character offsets (`char_count`), 0-based | all: after a syntax error `read_term/3` resumes after the next full stop | error; singletons as warnings positioned on the variable |
| z3 5.3.3 (executed) | stdout; continues after an error | `(error "line L column C: msg")`; responses in command order; `echo` text unquoted | 1/0 (bytes assumed) | every error | error; z3 accepts some ill-sorted terms cvc5 rejects (`(> x true)`) |
| cvc5 1.4.2 (executed) | stdout; warnings on stderr; stops at the first error | `(error "Parse Error: <file>:L.C: msg")`, or no position (`cannot push …` without `--incremental`); exit 1 | 1/1 | first | error |
| rudof 0.3.24, Turtle (rudof_elixir b9f5f4f, executed) | `Rudof.Session.read_data/3` → `{:error, %Rudof.Error{kind: :data_error, message: m}}`; the position is only in `m` | `… Parser error at line L between columns C and C2: msg`, or `… between line L column C and line L2 column C2: msg` | 1/1, code points, end exclusive | first | error |
| rudof 0.3.24, SPARQL (executed) | `Rudof.Session.load_sparql_query/2` → `:query_error` | `… error at L:C: expected one of …`: the furthest point the parser reached, often the end of the input rather than the fault; an undeclared prefix is reported as such a syntax error | 1/1, code points, one position | first | error |
| rudof 0.3.24, ShExC and ShapeMap (executed) | `Rudof.Session.check_shex/3` → `{:ok, {false, text}}`; `read_shex/3`, `read_shapemap/3` → `:shex_error` | `Parse error on line L, column C: msg`, then `Context:` lines, each the start of a production that failed, outermost first; an undeclared prefix has no position (`Alias 'ex' not found in prefix map`) | 1/1, code points | first | error |
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
- Include resolution (executed): SWI-Prolog 10.0.1 reads `:- [defs].` and
  `:- include(defs).` as `defs.pl` beside the loading file; clingo 5.8.2 reads
  `#include "defs".` as `defs` beside the including file, adding no extension, and an
  included file's messages name its path; egglog reads `(include "defs")` from the
  working directory, and `Egglog.parse/1` does not open it.
- Prolog linting lives in Prolog, `loge_prolog/priv/loge.pl`, loaded into a fresh `swipl`:
  `read_term/3` over the program file in a temporary module, executing `op/3` directives;
  singletons located by walking `subterm_positions`; `_`-prefixed names skipped, and a
  query's variables, which are what it asks for. The same reading gives the goal of each
  `?- Goal.` by its position. `SWI.load/3` consults a path, and the bridge cannot skip
  terms of it, so a `user:term_expansion/2` clause in `loge.pl` expands each query to
  nothing while consulting; the engine then asks the goals one by one. The bridge runs
  each query in a Prolog engine whose stream aliases are its own: output is
  captured by redirecting in the worker thread (a loaded directive) and again in each
  `solve/2`. `SWI.query/3` raises on timeouts and Prolog errors; `Loge.Prolog.Swipl`
  rescues `SWI.Error` once per answer pull to keep earlier answers.
- SMT-LIB lint cannot come from the solvers (first error, full run, and they disagree on
  what is well-sorted): `Loge.Smtlib.Sexp` reads S-expressions with byte spans, and
  `Loge.Smtlib.Commands` checks command names, arity and the kinds of name positions
  (SMT-LIB 2.6 §4.1), only once the script reads. Solver errors become diagnostics in
  the outcome, not a failed run; a single `check-sat` the solver stopped before
  answering is `:input_error` when it reported an error, `:stopped` otherwise. Both solvers flush each response through a pipe, so a
  run killed at its deadline keeps its earlier answers; their own limits are not used
  (z3 `-T` and cvc5 `--tlimit-per` only answer `unknown`; cvc5 `--tlimit` aborts with
  a core dump).
- egglog: `EGraph::parse_program` is separate from `run_program`; the NIF calls it with
  filename `None`. Runs are not interruptible: a run whose caller died kept a core busy
  (measured); egglog's own early stop is only triggered from primitives. Hence
  `Loge.Peer`.
- rudof (rudof_elixir b9f5f4f, rudof 0.3.24; executed in this Debian trixie container,
  glibc 2.41, OTP 29, with rudof_elixir as a path dependency of a scratch project):
  - The linux x86_64 bundle loads; rudof_elixir's own `mix test` passes 120 of 123. The
    three failures render SVG through Graphviz's `dot`, not installed here; images are
    the only use of the bundled `rudof_render` executable, and Loge needs none. The NIF
    links libc and libm and a bundled `libgcc_s` (RUNPATH `$ORIGIN`); its README
    requires glibc 2.39. Not tried: `.devcontainer` (no podman here) and the NixOS host,
    where `rudof_render`'s interpreter `/lib64/ld-linux-x86-64.so.2` is missing without
    nix-ld; the NIF itself is loaded by the BEAM's own loader.
  - Cost: `read_data/3` takes about 176 ms of CPU whatever the input (180 ms empty,
    220 ms for 5000 triples, about 88 ms before a parse error); `read_shacl/3` reads
    the same Turtle in 0.3 ms with the same parser messages; `load_sparql_query/2`
    0.1 ms, `check_shex/3` 1 ms, a fresh session 1 ms. `Rudof.query/3` in the node is
    about 177 ms, through `Loge.Peer.call/3` about 335 ms (445 ms the first time).
  - Native work runs on dirty CPU schedulers and has no timeout. A query whose caller
    was killed kept a core busy (measured 2 s later), though the node went on
    answering; in a `Loge.Peer` the peer was gone within 1 s of the caller's death.
  - A ShExC `IMPORT <url>` is fetched while the schema is checked, without a timeout:
    `check_shex/3` with an import from a local server that never answers had not
    returned after 5 s. A lint of ShExC, or of a shape map, which reads the schema,
    can therefore block for good in the node.
  - Results: `Rudof.query/3` gives `%{kind: :select, variables, rows}` (terms as
    N-Triples strings, `nil` unbound; an empty result has `variables: []`),
    `%{kind: :ask, boolean}`, or `%{kind: :graph, graph}` in N-Triples-like Turtle for
    `CONSTRUCT` and `DESCRIBE`. `Rudof.validate_shacl/3` gives `%{conforms, results}`,
    each result `%{focus_node, path, value, severity, source_shape,
    constraint_component, messages: [%{text, lang}]}`, IRIs without `<>` and `value` a
    term string. `Rudof.validate_shex/4` gives `%{conforms, entries}`, each `%{node,
    shape, status: :conformant | :nonconformant, details}`; an unknown shape label is a
    nonconformant entry, not an error.
  - A shape map is read after data and a schema (`No data loaded`, `No ShEx schema
    loaded`). Its nodes are read with the data's prefixes and its shape labels with
    the schema's (`Available aliases` names them); it declares none of its own.
  - `Rudof.validate_shacl/3` with one text as data and as shapes validates the graph
    against the shapes it contains.
  - Endpoints: `Rudof.Session.list_endpoints/1` knows `UniProt`, `togoid`, `mardi`,
    `Wikidata_qlever`, `DBpedia` and `Wikidata` with their URLs. `read_endpoint/2`
    takes such a name, case-insensitively, or a URL, and sends nothing; a query then
    sends `GET <url>?query=…` with `accept: application/sparql-results+json`
    (observed against a local server only).
  - Hence: runs in a `Loge.Peer`, whose end is also how a time limit ends one, as
    rudof has no limit of its own. Parsing Turtle and SPARQL ends and needs no network,
    so those lints can run in the node; a ShExC or shape-map lint fetches imports, so
    it runs in a peer with a deadline, as the ASP lint has one.

## 7. Editor facts (Kino 0.19.1, Livebook main on 2026-11-11)

- The editor is CodeMirror 6. Its source is `kino_loge/assets/editor.js`; `npm run build`
  there bundles it with esbuild into `kino_loge/lib/assets/editor.js`, which is committed
  (as Kino packages commit their builds) and imported by `cell.js`. The bundle is 596 kB
  with the eight grammars. Node comes from `.devcontainer`: `docker.io/library/node:26-trixie`
  as user `node`, the image the Node of the agent's container is copied from, so both
  sides share `node_modules` and the lockfile.
- Output: `KinoLoge.Code` shows a `{:text, text, language}` view through the same bundle,
  read-only, with line numbers, search and coloured brackets, at most 300 px high. A
  text view without a language and the raw output stay terminal text: raw output mixes
  languages, so an engine names the parts that are in one. A TPTP engine's outcome has
  what the system derived as its output, in TPTP: the derivation
  (`AtpClient.Result.derivation/1`), else the interpretation (`interpretation/1`). When
  neither reads, what the system printed is shown as TPTP text views titled by dataform
  (`CNFRefutation`): the solution region of a TSTP reply (`details.tstp`, SystemOnTPTP's
  default) and each SZS output block (`AtpClient.Result.blocks`). The Engine cell shows a bound input with the same
  read-only viewer in place of its editor. Both cells wire the editor and its
  diagnostics through the hand-written `editing.js`.
- Beside editing: search and replace (`@codemirror/search`, Ctrl+F), matching brackets,
  and brackets coloured by nesting depth. The depth is read from the syntax tree: an
  opening bracket is a node with `NodeProp.closedBy` (set by the grammar), its
  closer the next node named in that list, as `@codemirror/language` matches brackets;
  brackets in comments and strings stay uncoloured.
- Grammars are npm packages imported in `editor.js` and keyed by the name
  `c:Loge.Language.editor_language/0` returns; `nil` or a name without a grammar is plain
  text. A language change reconfigures the editor in place. Bundled, keyed by language id:
  `codemirror-lang-tptp`, `-asp`, `-dimacs`, `-egglog`, `-smtlib`, `-swipl` (as `prolog`),
  and from other authors `codemirror-lang-turtle` 0.0.2 and `codemirror-lang-sparql`
  2.1.0. Checked in Node only: both parse and highlight samples, but only Turtle's
  `[ ]` carry `closedBy`, so their other brackets are not coloured by depth, and SPARQL
  leaves `{ }` and prefixed names untagged. ShExC (`"shex"`) and shape maps
  (`"shapemap"`) have no grammar yet and are plain text.
- Collaboration is `@codemirror/collab` with the cell process as the authority. A client
  pushes `%{"version" => n, "updates" => [%{"clientID" => id, "changes" => change_set}]}`.
  The cell applies a push made against its current version (`KinoLoge.ChangeSet`, lengths
  in UTF-16 code units), adds the number of updates to the version and broadcasts the
  updates; any other push is dropped, and its client rebases on the broadcasts it was
  missing and pushes again. The cell keeps the source and the version, no update log:
  every client receives every broadcast in order, and a client that connects later starts
  from the source and version of `handle_connect/1`.
- Evaluation: Livebook awaits the promise of the `ctx.handleSync` handler before it pings
  the cell and evaluates (`iframe/v6.html`, `js_view.js`). The handler resolves once the
  cell has confirmed every edit of that client, so the evaluated source includes them.
- Persistence is unchanged: the source is the `"source"` attr, reported after every
  applied push. The version is not stored; it counts from 0 when the cell starts. On a
  crash the cell shows "Restart Smart cell" and `init/2` receives the last reported attrs.
- Diagnostic keys (the format of kino#522): `:line` (1-based, required), `:column`
  (1-based, default first non-whitespace character), `:end_line` (default `:line`),
  `:end_column` (exclusive, default end of `:end_line` without trailing whitespace),
  `:severity` (`:error | :warning | :info | :hint`), `:description`. Columns count UTF-16
  code units. `editor.js` turns them into `@codemirror/lint` diagnostics, dropping those
  whose line is outside the document and clamping columns to the line. Each update
  replaces all diagnostics; they are sent again in `handle_connect/1`.
- Keys: Livebook's iframe (`iframe/priv/static/iframe/v6.html`) replicates every `keydown`
  to the parent page with `isTargetEditable`, so notebook shortcuts that work while
  typing in an input keep working. Read in the source, not tried in Livebook.
- Not provided, unlike Livebook's own editor: the user's editor settings (theme, font
  size, vim/emacs keys), remote cursors. The theme copies Livebook's dark default.
- Verified outside Livebook: three simulated clients with random interleavings converge
  (200 rounds); `KinoLoge.ChangeSet` agrees with CodeMirror on the 9906 change sets of
  that run; `cell.js` with two clients in headless Chromium against a stand-in for the
  cell syncs edits, highlights TPTP, colours brackets, searches, draws diagnostics,
  switches grammar and holds the sync handler until its edits are confirmed; `code.js`
  highlights, scrolls and searches a 31-line derivation and rejects typing. In Livebook
  (released escript, `notebooks/tptp.livemd`, headless Chromium) every Logic Engine cell
  loads its editor with highlighting, coloured brackets and diagnostics; editing by two
  browsers, evaluation and highlighted output are not yet tried there. These runs predate
  the other grammars and brackets found by `closedBy`; those are checked in Node only
  (bracket depths in ASP, egglog, SMT-LIB, SWI-Prolog and TPTP samples).
- Livebook's own editor highlights TPTP since livebook#3234 (merged), in Markdown fences
  and code cells; the smart cell does not depend on it.

## 8. Translations

A translation is an engine with the task `{:translate, to, preserves}` (§3).

- Written in Elixir, as a function of the source. No external tool and no remote service
  at run time. The tools of the TPTP World and Vampire are the models for what a
  translation does and the references it is verified against (§9), not dependencies.
- In the package of its source language. It emits the target's text itself, so
  `loge_tptp` produces DIMACS text without depending on `loge_dimacs`.
- Total on its language: an input outside its fragment is an outcome with
  `:inappropriate`, not an error and not a best effort.
- Recorded. Where source and target are TPTP, every output statement carries an
  `inference(rule, [status(…)], [parents])` annotation, and `details.derivation` holds
  the whole derivation as TPTP text: the input statements as leaves, every intermediate
  statement, and the output. `Tptp.Derivation` reads it and GDV verifies it (§9). Rule
  names and step statuses follow E's proofs, which GDV has been used to verify: `fof_nnf`,
  `variable_rename` and `split_conjunct` with `status(thm)`, `skolemize` with
  `status(esa)`, `assume_negation` with `status(cth)`, and `introduced(definition)` for
  a named subformula.

`preserves` relates the input, as Ax, to the output, as C. The reading is Loge's own:
for a TPTP problem Ax is the axioms with the negated conjecture, the set a refutation
starts from; across logics (a modal problem and its THF embedding) each side has its
models in its own logic. Where no value of the ontology states a relation or a result,
Loge names its own (PLAN, open questions). Loge states the status and derives nothing
from it yet: the rules for carrying a verdict back from an output to its input are not
written.

`tptp` yields a concrete syntax tree and elaborates nothing (`Tptp.Node`), so the
translations compute on a formula type of their own, `Loge.Tptp.Formula`: terms, atoms,
connectives and quantifiers, read from nodes and printed back through `Tptp.Printer`.
It lives in `loge_tptp`, the adapter between `tptp` and Loge; `tptp` stays a reading of
the syntax.

First translations (phase 8):

| Engine                       | From → to                                           | Preserves           | Model and reference                                                             |
| ---------------------------- | --------------------------------------------------- | ------------------- | ------------------------------------------------------------------------------- |
| `Loge.Tptp.Engines.Clausify` | FOF → CNF                                           | `:equi_satisfiable` | ECNF 3.5.1 (E), VCNF 4.8 (Vampire)                                              |
| `Loge.Tptp.Engines.Ground`   | CNF with no function symbol of arity above 0 → ground CNF | `:equi_satisfiable` | EGround 3.5.1                                                              |
| `Loge.Tptp.Engines.Dimacs`   | ground CNF without equality → DIMACS                | `:equi_satisfiable` | none; an atom per variable, the table in `details.atoms` and as `c` comment lines |

Later, by course topic (phase 9): non-classical TPTP → THF (ATFLET 1.9.5, the logic
embedding tool), TF0 → FOF (Monotonox-2FOF), and the standard translations between
description logic, modal logic and first-order logic. Tool names and versions are those
SystemB4TPTP listed on 2026-11-14.

## 9. Verifying translations

A translation is checked by tools that share none of its code. There are four checks.
The first runs with the test suite. The other three run before a package is published
and never in CI: they need the network, the TPTP library and minutes to hours.

| Check        | What it establishes                                                                                                                                                                                              | With                                                                                                             |
| ------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| Properties   | On generated small inputs: the output is in the target fragment, introduced symbols are fresh, and for propositional inputs the relation holds by truth table (input and output are equisatisfiable, and each model of the output restricted to the input's atoms is a model of the input) | StreamData, in `mix test`                                                                 |
| Derivation   | Each step of `details.derivation` has the status it claims, and the derivation is well-formed                                                                                                                    | GDV through `AtpClient.verify/2`: trusted ATP systems discharge an obligation per step                           |
| Status       | On problems whose status is recorded, solving the output gives the status the relation predicts                                                                                                                  | TPTP library headers (`Tptp.Header.status/1`); a reference prover through the engines of `loge_tptp`; clasp for DIMACS |
| Differential | The reference tool's output for the same input has the same status as ours under the same prover                                                                                                                 | `AtpClient.SystemOnTptp.process_problem/3` with ECNF, VCNF, EGround, ATFLET, Monotonox-2FOF                      |

Outputs are compared by status, never by text: two clausifiers rarely print the same
clauses.

The three later checks are ExUnit tests tagged `:verification`, excluded in
`test_helper.exs` and run with `mix test --only verification`. The figures of a run are
recorded in the package's `VERIFICATION.md`: date, package version, TPTP version and the
selection of problems, the versions of the tools, and per check the counts of agreeing,
disagreeing and undecided cases, with every disagreement listed. A reference prover's
timeout is undecided, not agreement. A package is published only with a record for that
version and no disagreement in it.

This is evidence on a corpus, not a proof of the algorithm. A translation's moduledoc
says so and points to the record.

## 10. Consumers

A consumer needs `loge` and the language packages it wants, nothing else. `kino_loge` is
one; `loge_mcp` will be another and is not planned here. What every consumer may rely
on, and what the tests of `loge` hold with fake modules:

- Discovery is data. `Loge.Registry` lists languages and engines and finds one by the
  string form of its id. An engine's `label/0`, `languages/0`, `task/0`, `roles/0`,
  `controls/0` and `config_schema/0` say everything needed to call it. `translations/0`
  gives the edges between languages.
- External values are read by the core: `Loge.Control.cast/2` for control values,
  `Loge.Variable.parse/1` for names. A consumer makes no atom from its input.
- One call per purpose: `Loge.lint/3`, `Loge.run!/3` or `c:Loge.Engine.run/2`,
  `Loge.configure!/2`. Runs go under `Loge.Run`, and the death of the caller cancels.
- Results are data: an outcome's status, views of the closed set (§3), raw text and
  output; diagnostics with ranges; errors as the sentence of `format_error/1`.
- Nothing in `loge` or in a language package depends on Kino or on a transport.

`loge_mcp`, when it comes, is a transport over these: a catalogue built from the
registry, `lint` and `run`. If it needs something from a language package that this
list does not give, the list is what changes.

## 11. Sources

Scope and cells: [kino_db](https://github.com/livebook-dev/kino_db) (connection and
query cells linked by variables),
[Livebook 0.8](https://livebook.dev/blog/whats-new-in-livebook-0-8) (dependency tracking
between cells), [SWISH](https://arxiv.org/abs/1808.08042) (program and query cells),
[SystemB4TPTP](https://tptp.org/cgi-bin/SystemB4TPTP),
[SystemOnTPTP](https://tptp.org/cgi-bin/SystemOnTPTP),
[SystemOnTSTP](https://tptp.org/cgi-bin/SystemOnTSTP) (problem tools, solvers, solution
tools), [RDF Playground](https://www.aidanhogan.com/docs/rdf-playground.pdf),
[rudof_elixir](https://github.com/davfuenmayor/rudof_elixir),
[rudof](https://github.com/rudof-project/rudof),
[codemirror-lang-sparql](https://github.com/aatauil/codemirror-lang-sparql),
[codemirror-lang-turtle](https://github.com/aatauil/codemirror-lang-turtle).
Translations and their verification: Sutcliffe,
[Semantic Derivation Verification: Techniques and Implementation](https://doi.org/10.1142/S0218213006003119)
(GDV); Reger, Suda and Voronkov,
[New Techniques in Clausal Form Generation](https://doi.org/10.29007/dzfz) (Vampire's
clausifier); Steen,
[An Extensible Logic Embedding Tool for Lightweight Non-Classical Reasoning](https://ceur-ws.org/Vol-3201/paper13.pdf);
[TPTP World Infrastructure for Non-classical Logics](https://arxiv.org/abs/2508.09318).
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
