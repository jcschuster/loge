# Verification of the translations of `loge_tptp`

The record of the checks of OUTLINE §9 that read the TPTP library: `mix test --only
status` and `mix test --only differential`, with `$TPTP` the root of the library and the
judges on `PATH`. A problem is drawn as `test/support/verification.ex` says: its status
fixes whether the axioms with the negated conjecture are satisfiable, its rating is at
most 0.5 and it has at most 200 kB with its includes. The first 20 problems an engine
translates, or runs past the deadline of 30 s on, are checked, in the order of a hash of
their names. An undecided case is a judge that timed out or gave up, or a translation
past the deadline; it is not agreement.

This is evidence on a corpus, not a proof of the translations.

## 2026-11-20, `loge_tptp` 0.1.0

TPTP v10.0.0. Vampire 5.1.0 (`--mode casc`, then `--saturation_algorithm fmb`, 10 s and
2000 MB each), z3 5.3.3 (`-T:20`; `-dimacs` for DIMACS). Problems per check: 20.

### Status

The answer of the judge on the output against the status recorded for the input.

| Engines                | Forms        | Judge   | Agree | Disagree | Undecided | Outside |
| ---------------------- | ------------ | ------- | ----: | -------: | --------: | ------: |
| `Clausify`             | FOF          | Vampire |    20 |        0 |         0 |       0 |
| `Fof`                  | CNF          | Vampire |    17 |        0 |         3 |       0 |
| `Tff`                  | FOF, CNF     | Vampire |    17 |        0 |         3 |       0 |
| `Thf`                  | FOF, CNF, TF | Vampire |    16 |        0 |         4 |       0 |
| `Untyped`              | TF           | Vampire |    16 |        0 |         4 |     203 |
| `Ground`               | CNF          | Vampire |    15 |        0 |         5 |     152 |
| `Ground`, `Dimacs`     | CNF          | z3      |    16 |        0 |         4 |     160 |
| `Smtlib`               | FOF, CNF, TF | z3      |    18 |        0 |         2 |       5 |

Undecided: `Fof` and `Tff` KLE147-10, LAT099-1, LCL278-3; `Thf` the same and LCL267-3;
`Untyped` COM270_1, COM290_1, HWV045_3, HWV046_3; `Ground` HWV071-1, NLP120-1,
SYN507-1, SYN876-1, SYN878-1; `Ground`, `Dimacs` NLP120-1, SYN507-1, SYN876-1,
SYN878-1; `Smtlib` COL043-2, LAT099-1.

Not checked: `Prolog`, as SWI-Prolog's depth-first search does not decide a problem.
The derivation check does not apply yet: no translation records `details.derivation`.

### Differential

The answer of Vampire on our output against its answer on the output of a reference
tool of SystemB4TPTP for the same input, fetched through
`AtpClient.SystemOnTptp.process_problem/3`. Problems drawn as above.

| Engine     | Reference      | Agree | Disagree | Undecided | Outside |
| ---------- | -------------- | ----: | -------: | --------: | ------: |
| `Clausify` | ECNF 3.5.1     |    20 |        0 |         0 |       0 |
| `Ground`   | EGround 3.5.1  |     4 |        0 |        16 |     152 |

Undecided for `Ground`: EGround printed no clauses. It says `Inappropriate` for
PUZ013-1 and SYN030-1 (SPC `CNF_UNS_PRP`), and `Unknown` with an empty output, after
0.00 s, for the EPR problems GRP123-2.005, GRP123-8.003, GRP131-2.002, HWV071-1,
NLP120-1, SYN130-1, SYN153-1, SYN172-1, SYN213-1, SYN278-1, SYN284-1, SYN507-1,
SYN876-1 and SYN878-1. Whether SystemB4TPTP runs EGround with other options for these,
or the request lacks a field, is not known.
