# Validation and in-game tests

Run validation from the repository root:

```sh
./validate.sh
./validate.sh --in-game
```

Ordinary validation runs lint, static checks, the mock-based Lua regressions,
and runner failure/cleanup checks. It does not need Factorio. `--in-game` also
runs the working mod in a real engine and fails if Factorio is missing. Both
suites contribute to the exit status; engine tests still run when a fast check
fails (including pending non-English translations).

## Engine setup

The runner prefers `/Applications/factorio.app/Contents/MacOS/factorio`, then
`factorio` on `PATH`. It needs a compatible Factorio 2.1 installation with the
quality expansion data. The initial suite was developed against 2.1.17.
No desktop, player, clicks, or account credentials are needed.

```sh
./validate.sh --in-game --factorio /path/to/factorio --data /path/to/data --timeout 120
```

`QC_FACTORIO` and `QC_FACTORIO_DATA` provide the same overrides. An explicit
missing executable or data directory fails instead of falling back to a different
installation. `--timeout` is the maximum wall-clock seconds **per launch**.

The runner copies runtime files into a new temporary workspace, enables only
base, quality (and its recycler dependency when present), Quality Control, and
a fixture mod, then:

1. Creates a deterministic initial save.
2. Runs a server bound to `127.0.0.1` on an ephemeral port, with public/LAN
   visibility disabled and a random game password. It advances normal ticks
   without players, earns progression, and saves `qc-earned.zip`.
3. Waits for a complete, readable checkpoint, stops its server, and reloads the
   earned save for 600 benchmark ticks. This load must verify earned state and
   report all required success markers.

Sandboxed environments must permit the private loopback socket. The runner
does not read or modify normal saves, mods, or user configuration. Its own
configuration, mods, initial save, earned checkpoint, and `create.log`,
`progress.log`, and `reload.log` remain in the printed workspace for diagnosis.
Remove that directory when finished. Assertion errors, premature exits, missing
markers, and timeouts fail; the runner terminates its own processes on exit.

## Engine cases

| Case | Engine boundary covered |
| --- | --- |
| `capped_host` | A real producer pays for an independent module upgrade in a capped uncommon beacon; host identity, total item count, and recalculated speed effect are checked. |
| `capacity` | Quality Control upgrades a fixture assembler through four → two → four slots. Per-slot bonuses, dormant history, inspection output, actual inventory capacity, and batch-budget accounting are checked. |
| `late_insert` | An empty capped host keeps receiving visits while its surface progresses. Later insertion keeps the slot bonus, earns nothing from already-observed empty intervals, and begins earning from new work without rebuilding tracking. |
| `earned_reload` | A checkpoint contains an observed failed-roll bonus and consumed meter bookmarks. Reloading preserves them, pays no historical credits while idle, and resumes progression after production restarts. |

The capacity fixture uses `quality_affects_module_slots` and
`module_slots_quality_bonus = {normal = 2, uncommon = 0, rare = 2, ...}` on a
two-slot assembler. These are real engine inventory changes during production
`order_upgrade` / `apply_upgrade`, not resized Lua tables. A terminal-quality
module is inserted in a restored slot to verify its capacity without resetting
the retained bonus.

The fixture uses short recipes, small manufacturing-hour thresholds, and
zero quality-chain skip probabilities. Setup hooks seed distinct slot bonuses
and guarantee selected host/module successes. Failure accumulation is earned
by observing a real failed roll, without relying on an exact RNG sequence.
Both tick deadlines and process timeouts bound the run.

`hooks.lua` is loaded only into the temporary Quality Control copy. It reads
tracking state, seeds setup bonuses/chances, sets the runtime batch budget,
and exposes the existing module inspection formatter. It never invokes or replaces the production processing
loop, engine API objects, RNG, or `on_load` handler. No test interface is shipped
in the mod; `package.sh` already excludes `tests/`.

Add engine tests for uncovered engine boundaries or concrete regressions.
Keep probability permutations and artificial failures in the cheap Lua suite;
large-save profiling belongs in a separate benchmark. The runner is adapted
from the sibling Auto-Loader project's `tests/run_factorio.py`.

## Fast checks

The `test_*.py` files check metadata, changelogs, localization, whitespace,
Lua syntax, require placement, global usage, and restricted `on_load` access.
`test_independent_modules.py` runs the production Lua modules against the small API
doubles in `tests/lua/independent_modules.lua`.
`test_celebrations.py` checks each alert toggle alone, combined machine/module
delivery, recipient and surface selection, modded qualities, bursts, and drawing
cleanup after expiry, setting changes, disconnects, force changes, and invalid
render objects. Reload coverage retains storage while reloading the Lua module;
it does not substitute for engine serialization or client-side visual/audio review.
The headless engine suite has no connected players and does not exercise alert
presentation. For a client playtest, enable each new setting separately and then
together, upgrade machines and independent modules, and check remote view and
different surfaces. Verify a second same-force player sees only their chosen
effects, and save/load while rings or badges are active.
`test_factorio_runner.py` checks discovery overrides, workspace isolation,
required markers, assertion failures, process exits, timeouts, and cleanup
using small subprocesses without requiring Factorio.

Add new regressions to the relevant existing suite, and run `./validate.sh`.
Production static checks deliberately exclude fixture files under `tests/`;
luacheck still checks the Lua fixtures. Do not loosen production checks to
accommodate test hooks.
