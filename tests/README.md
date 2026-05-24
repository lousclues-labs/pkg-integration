<!-- SPDX-License-Identifier: GPL-3.0-only -->

# Tests

Two suites live here:

- **`unit/`** runs against in-process fixtures. No network, no
  container, no real `fpm`. Each test builds a synthetic stage,
  invokes one library, and asserts on the result. The suite is
  expected to finish in under a second on a developer laptop.
- **`smoke/`** runs end-to-end onboarding and packaging through the
  CLI surface. The packaging smoke uses a shim `fpm` so it does not
  require a real fpm install.

Run them with:

```sh
make test              # unit only (the inner loop)
make smoke             # smoke only (slower; runs fpm shim)
make ci                # everything CI runs (lint + test + smoke)
tests/run_tests.sh manifest   # filter by substring
```

## Harness

`tests/run_tests.sh` discovers `tests/unit/test_*.sh`, runs each in a
subshell with `$FRAMEWORK_HOME` and `$TEST_LIB` exported, and tallies
pass/fail. Smoke tests run separately because they are slower and
have a different output cadence.

A test is "passing" when it exits 0. Use `assert_done` at the end of a
test body to translate the per-assertion failure count into an exit
code.

## Assertion helpers (`tests/_assert.sh`)

All helpers print one line per assertion. `ok` lines are silent in
green; `fail` lines are noisy and pin the caller's `file:line`.

| helper | shape |
|---|---|
| `assert_eq <actual> <expected> [label]` | string equality |
| `assert_neq <actual> <forbidden> [label]` | string inequality |
| `assert_contains <haystack> <needle> [label]` | substring present |
| `assert_not_contains <haystack> <needle> [label]` | substring absent |
| `assert_rc <expected-rc> <cmd...>` | run cmd, check exit code |
| `assert_file_exists <path>` | path exists |
| `assert_file_executable <path>` | path has +x |
| `ok <label>` | manual pass (you did the comparison yourself) |
| `fail <label>` | manual fail (with auto-incremented counter) |
| `assert_done` | exit 0 if all green, exit 1 otherwise |

Conventions every test follows:

1. `set -uo pipefail` (NOT `-e`; we want all assertions to run, then
   fail at `assert_done`).
2. `HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"` so
   the test can be run from any working directory.
3. `source "$HERE/../_assert.sh"` for the helper namespace.
4. Use `$FRAMEWORK_HOME` (exported by the harness) for repo paths.
5. Build fixtures under `$(mktemp -d)`; `trap 'rm -rf ...' EXIT` for
   cleanup.
6. End with `assert_done`.

## Writing a new test

Copy `tests/_TEMPLATE.sh` to `tests/unit/test_<name>.sh`, make it
executable (`chmod +x`), and fill in the body. The harness will pick
it up automatically.

Tests are named `test_<thing-under-test>.sh`. Plural is fine if the
test exercises several related properties of one thing (see
`test_workflow_action_pins.sh`). Single-issue regression tests get
named `test_<v1_2_2>_findings.sh` style: ties the test back to the
finding it pinned.

## Smoke vs unit (where things go)

The boundary is "what's mocked":

- **unit/**: every dependency is in-process or a stub. No CLI
  subprocess. Sub-second per test.
- **smoke/**: invokes `bin/pkg-framework` or `pkg/build.sh` as a
  subprocess and inspects exit codes + emitted files. May shim
  external tools (`fpm`) but exercises the real CLI surface.

If your test invokes the CLI to verify its UX (help text, exit
codes, error messages), it is a smoke. If it imports one library
and exercises one function, it is a unit.

## Why this harness (and not pytest / bats / shunit2)

Two reasons. First, the framework is bash-end-to-end and a bash
test harness keeps the dependency graph at one row (bash). Second,
the assertion vocabulary the project needs is small enough that the
helper file fits in a screen. Pulling in a framework here would
pay for capabilities the project does not need.

If the suite grows past ~30 tests or the helpers grow past ~200
lines, the calculus changes; re-open the question then.
