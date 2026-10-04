# ZX-Carrom review-fix runbook progress

This ledger follows `scratch/review-fix-runbook.md` in order. PASS is used only after every required proof for that group or gate has actually succeeded.

## Baseline and recovery

- Remote `main` was rechecked before resumed work and matched the handoff state.
- Runner state at resumed baseline check: 0 queued, 0 running.
- Accepted clean-build reference: run 97, successful.
- Source recovery: the local temporary checkout had expired. Recovered the source snapshot from the accepted run-97 release ZIP. Handoff verification established no net source change between the accepted runbook revision and the current remote tip; later commits changed release bookkeeping only.
- Authoritative runbook at the remote tip was re-read from disk after recovery and matched the accepted handoff copy.
- Toolchain recovery: built Pasmo from the user's fork with one temporary dependency workflow, downloaded its Linux artifact, then removed that workflow file. Packaged the user's SkoolKit fork the same way after the Pasmo runner finished, installed it locally, and removed that temporary workflow file. The target repository remained unpushed and had 0 queued/0 running workflows throughout.

# Phase 1

## Fix group 1A — Logical player identity and seat rotation

**Status: PASS**

- Affected files: `src/carrom.asm`, `src/core.asm`, `src/game.asm`, `tools/test_player_mapping.py`, `tools/sim.py`, `.github/workflows/build.yml`.
- Reproduction: confirmed from the recovered baseline. Planner/profile-name selection indexed physical `seat`, no logical-player map existed, and the game transition did not apply the doubles side change while retaining player identity.
- Repair summary: kept `seat` as physical N/E/S/W; added `player_at_seat`; fresh matches initialize logical players 0/1/2/3; planner names, planner weights, mover pair/colour, breaker selection, and result accounting resolve logical identity through the map; continuing games rotate the map clockwise. Reverse lookup examines exactly four entries and returns carry plus `$FF` when a player is missing. `validate_player_map` rejects missing, duplicate, or stray mappings; transition recovery resets a damaged map before applying the required rotation and signals carry.
- Positive tests: `tools/test_player_mapping.py` ran against a snapshot loaded from the freshly built TZX and passed identity initialization, first rotation `[3,0,1,2]`, profile/name retention for all four players, forced seat swap, two valid transitions ending `[2,3,0,1]`, and mapped breaker/colour selection.
- Rejection tests: the same assembled test rejected `[0,0,2,3]` and `[0,1,2,9]`; missing logical player 1 returned `$FF` with carry within the bounded reverse lookup; rotating corrupt input signalled carry and recovered to valid rotated identity `[3,0,1,2]`.
- Proof test catches old/bad behavior: built the untouched recovered baseline in a detached temporary worktree, loaded its TZX, then ran the new focused test against that old snapshot/symbol set. It failed with exit 1 because the required mapping/validation symbols do not exist in the old implementation. The temporary worktree was removed afterward.
- Regression checks: 150-second emulator acceptance with seed 4660 passed all prior runtime checks plus `four logical players` and `player map permutation`; all physical seats and logical players 0/1/2/3 took turns. `git diff --check` and the index vocabulary gate passed.
- Build/validator/runtime results: `PASMO=/tmp/pasmo-bin/pasmo python3 build.py` passed with a 24,829-byte game payload; TZX validator reported four blocks, ROM pilots 2824/2420, 256-pulse fast leaders, 855/1710 data pulses, and no pauses. Runtime TZX expansion and cycle-level loading reached PC 32768; focused assembled checks passed; 150-second emulator acceptance passed all checks. Exact-tape Fuse playback was not available locally because Fuse is not installed; this group therefore claims emulator proof only, not real-hardware proof.
- New defects: the handoff-identified unbounded reverse lookup was hardened before proof. During rejection-test design, corrupt maps were also found to need explicit transition validation rather than blind rotation; `validate_player_map` plus deterministic recovery repaired that gap. The first rejection-test cycle budget was too small and stopped a valid bounded routine at 203 T-states; raising the test-only cap to 1000 fixed the harness without changing game behavior.

## Fix group 1B — Queen-eligibility history by coin colour

**Status: PASS**

- Affected files: `src/game.asm`, `tools/test_queen_history.py`, `.github/workflows/build.yml`.
- Reproduction: confirmed from disk before repair. `had[colour]` was set only after a no-striker stroke that pocketed one or more coins of the mover's own colour. Opponent-colour pocket events did not set that colour's history, and an own coin pocketed with the striker was excluded. Queen targeting later read `had[colour]` and `dues[colour]`.
- Repair summary: added `record_coin_history`, called for every ordinary coin in `pk_ids` while pocket events are counted. The routine records history by the coin's own colour before any Due or striker return processing. Board setup remains the only place that clears `had[]`.
- Positive tests: `tools/test_queen_history.py` passed against a fresh TZX-loaded snapshot. An opponent-colour pocket set only that colour's history; an own coin pocketed with the striker was physically returned while its history stayed set; Queen targeting included the Queen after qualifying history with no Due.
- Rejection tests: no-pocket and return/owe processing left both history flags clear; Queen targeting stayed blocked without history; an outstanding Due blocked Queen targeting even with history set.
- Proof test catches old/bad behavior: built untouched `HEAD` in a detached temporary worktree and ran the new focused test against its fresh snapshot. It failed with exit 1 at `opponent-colour pocket did not record that colour`. The temporary worktree was removed.
- Regression checks: 1A player-map assembled checks and 1B queen-history assembled checks both passed; 150-second emulator acceptance with seed 4660 passed all runtime checks; `git diff --cached --check` and the index vocabulary gate passed.
- Build/validator/runtime results: `PASMO=/tmp/pasmo-bin/pasmo python3 build.py` passed with a 24,829-byte game payload; TZX validator reported four blocks, ROM pilots 2824/2420, 256-pulse fast leaders, 855/1710 data pulses, and no pauses. Fresh cycle-level tape playback reached PC 32768 before the focused checks. Emulator proof only; no real-hardware claim.
- New defects: none.

## Fix group 1C — Consecutive-pass state

**Status: PASS**

- Affected files: `src/carrom.asm`, `src/game.asm`, `tools/test_pass_replay.py`, `.github/workflows/build.yml`.
- Reproduction: confirmed from disk. The old `consecutive` byte incremented on successful continuation strokes and was cleared by every turn advance, so it could never count consecutive pass events or reach a replay threshold.
- Authoritative threshold: ICF Law 137 in upstream `reference/ICF-Carrom-Official-Rules.txt` states that when players pass their turns consecutively three times each, that board is cancelled and replayed. ZX-Carrom is doubles-only with four physical players, so the explicit threshold is 12 consecutive turn passes.
- Repair summary: replaced `consecutive` with `pass_streak`; `pass_turn` increments only on an actual turn pass and, at 12, clears the streak, keeps the same board counters, and schedules `PH_NEWBOARD` so the normal clean `setup_board` path replays that board. `record_progress` clears the streak on a lawful continuation. Fresh match and board setup also clear it.
- Positive tests: `tools/test_pass_replay.py` passed against a fresh TZX-loaded snapshot: passes 1-11 did not replay; pass 12 signalled exactly one replay; a progress event reset the sequence; ordinary own-coin continuation reset rather than incremented the streak; fresh match and board setup cleared stale state.
- Rejection tests: after a threshold replay, the next pass began a new streak rather than retriggering; one pass followed by progress and then 11 passes stayed below threshold; the fresh twelfth pass alone replayed.
- Proof test catches old/bad behavior: a disposable controlled fixture changed only `PASS_REPLAY_LIMIT` from 12 to 13. The focused test rejected it immediately with exit 1 (`doubles threshold is not 12`). The disposable fixture was removed.
- Regression checks: all Phase-1 focused checks (player mapping, Queen history, pass replay) passed together; 150-second emulator acceptance with seed 4660 passed every runtime check; index vocabulary gate and `git diff --cached --check` passed.
- Build/validator/runtime results: production build passed under `/tmp/pasmo-bin/pasmo`; final TZX validation and fresh cycle-level tape load to PC 32768 passed before the focused tests. Emulator proof only; no real-hardware claim.
- New defects: none.

## Phase 1 gate

**Status: PASS**

- Current and earlier focused tests: PASS — player mapping, Queen history, and pass replay all passed against the snapshot cold-loaded from the final Phase-1 TZX.
- Production build: PASS — two sequential `PASMO=/tmp/pasmo-bin/pasmo python3 build.py` runs completed from the same staged tree. Final game payload: 24,829 bytes.
- Validators: PASS — TZX validator reported four blocks, ROM pilots 2824/2420, fast leaders 256/256, turbo data pulses 855/1710, correct payload length, and no pauses.
- Runtime acceptance: PASS (emulator) — three separate cycle-level tape loads reached PC 32768; 150-second acceptance passed four physical seats, four logical players, mapping permutation, turn flow, sound cycle, speed toggle, pause/resume, restart, live points, returns, counter reset, groove activity/loop, effects idle state, phase sanity, screen/loading/HUD/ribbon/title/starfield checks; clean quit-to-BASIC passed with PC 5625 and BASIC report 9. Exact-tape Fuse was unavailable locally, so no real-hardware claim is made.
- Two clean builds and byte comparison: PASS — `carrom.bin`, `carrom_fast.tzx`, and `zx-carrom.zip` were byte-identical. Build-1 checksums: binary `a1c5bc94ed425b896808837de30b0459ff66bb69799f6d5d83290b4035fbf863`; TZX `8f034d841ddecafb6860c79567b8c07549fc184ab84cb0037105732e631337b5`; ZIP `a88c24bfe3d1f4f031eec69266a1bb99c9d7ffd83112f05cf987fa3202caba28`.
- Restricted-vocabulary result: PASS — index gate clean; `git diff --cached --check` clean.
- Runner-state check immediately before checkpoint push: PASS — remote `main` unchanged; 0 queued, 0 running.
- Checkpoint push: PASS — Phase 1 checkpoint `0dbc00ca4f6872b963c32ec26e2e6c250f036181` was pushed to `main` after the required zero-runner check.
- Authoritative workflow result: PASS — clean-build run 98 completed successfully for that checkpoint. It passed the vocabulary gate, authoritative Pasmo build, two clean production builds plus byte comparison, runtime tape/play checks including all three focused Phase-1 checks, checksum recording, clean-source verification, accepted-release round trip, and artifact uploads. The workflow refresh commit advanced `main` to `7df4a3fe24736348de4e2fc6d2f4aa08551480f7`; comparison showed only `dist/CHECKSUMS`, `dist/carrom_fast.tzx`, and `dist/zx-carrom.zip` changed. Post-run state: 0 queued, 0 running.

# Phase 2

## Fix group 2A — Extra-board breaker selection
**Status: PASS**

- Affected files: `src/carrom.asm`, `src/game.asm`, `tools/test_extra_breaker.py`, `.github/workflows/build.yml`.
- Reproduction: after a tied eighth board, `ph_afterboard` scheduled another board but `setup_board` still derived the breaker from `boards_in_game + games_played + break_off`; no fresh extra-board toss state existed.
- Repair summary: added one-shot `extra_board` plus `extra_breaker` state. A tied eighth-board transition draws a fresh logical breaker 0..3; `setup_board` consumes that state only for the extra board, maps the logical player through `player_at_seat`, derives the logical white pair, and leaves normal-board rotation unchanged. `new_game` clears the extra-board state.
- Positive tests: `tools/test_extra_breaker.py` passed against a fresh TZX-loaded snapshot for injected tosses 0,1,2,3 under mapping `[2,3,0,1]`, with mapped physical seat and logical white pair verified for every toss; the tied eighth-board transition armed a fresh 0..3 selection.
- Rejection tests: counters were chosen so the old rotation formula disagreed with injected tosses; the toss won. With `extra_board=0`, stale `extra_breaker=3` was ignored and not consumed while ordinary rotation selected the expected breaker.
- Proof test catches old/bad behavior: the new focused test was run against the preserved Phase-1 snapshot/symbol set and exited 1 because `extra_board`/`extra_breaker` do not exist in the old implementation.
- Regression checks: Phase-1 player-map, Queen-history, and pass-replay assembled checks all passed on the same fresh snapshot; repository vocabulary gate and `git diff --cached --check` passed.
- Build/validator/runtime results: production build passed with Pasmo and a 24,831-byte game payload; TZX validation reported four data blocks, ROM pilots 2824/2420, fast leaders 256/256, 855/1710 data pulses, and no pauses. Fresh cycle-level tape loading reached PC 32768 before focused tests. Emulator proof only.
- New defects: none.

## Fix group 2B — Queen + own coin + striker continuation
**Status: PASS**

- Affected files: `src/game.asm`, `tools/test_queen_striker.py`, `.github/workflows/build.yml`.
- Reproduction: the pre-fix Queen+striker branch applied the same `rbefore==9`/Due/right-to-Queen restrictions even when one or more own coins were pocketed with the Queen and striker. Against the preserved Phase-2A snapshot, the new focused test failed at the full-set Queen+own+striker continuation case.
- Repair summary: split Queen+own-coin+striker from Queen+striker-without-own-coin. The former returns the Queen and own coin(s), applies the Due bookkeeping, and continues; the latter retains the prior restricted continuation rule. Due state is published before placement attempts. A failed Queen placement keeps nonzero Queen state and schedules a clean board replay rather than claiming a successful logical return.
- Positive tests: `tools/test_queen_striker.py` passed against a freshly cold-loaded snapshot. With `rbefore=9`, Queen+own coin+striker returned Queen and own coin, left one Due owed, and continued. With `rbefore<9` plus a spare pocketed own coin, the forced coin and Due were both returned and play continued.
- Rejection tests: Queen+striker with no own coin did not inherit continuation. A controlled impossible Queen placement scheduled `PH_NEWBOARD`, left the Queen body off-board with nonzero Queen state, preserved the owed Due, and did not claim the forced coin return succeeded.
- Proof test catches old/bad behavior: the same focused test was run against the preserved Phase-2A snapshot and symbol set; it exited 1 at `full-set Queen+own+striker did not continue`.
- Regression checks: Phase-1 mapping/history/pass tests plus the 2A extra-breaker test all passed against the fresh 2B snapshot; `git diff --cached --check` and the repository vocabulary gate passed.
- Build/validator/runtime results: production build under the authoritative Pasmo binary passed with a 24,831-byte game payload. TZX validation retained four blocks, ROM pilots 2824/2420, 256-pulse fast leaders, 855/1710 data pulses, and zero pauses. Fresh cycle-level tape playback reached PC 32768 before focused checks. Emulator proof only; no real-hardware claim.
- New defects: the first correct-looking implementation crossed the existing aligned-table memory boundary, shifting `QSQ` and `vars_end` by a page and tripping the production boundary assertion. The repair was reduced and reorganized without weakening that assertion; final addresses returned to the accepted layout (`QSQ=C200`, `code_end=DCE6`, `vars_end=E0FF`, `BGBUF=E100`).

## Fix group 2C — Two-colour Due recovery
**Status: PASS**

- Reproduction: confirmed from disk. Due repayment was keyed only to the moving coin colour, so an outstanding Due for the other colour could remain unpaid even when that colour had a pocketed coin available to return.
- First WIP repair: the return path was refactored toward a colour-parameterized `return_colour` routine, called first for the non-moving colour's existing Due and then for the mover colour's striker-forced returns plus Due. At that point `rret[colour]` was aliased onto existing scratch bytes to expose physical return counts for later 2D session accounting without allocating new persistent state.
- First gate result: the unchanged production memory-boundary assertion blocked that attempt. `PASMO=/tmp/pasmo-bin/pasmo python3 build.py` exits 1 because `vars_end < BGBUF` is false. A disposable diagnostic copy with only the generated failure directive commented out measured `QSQ=C300`, `code_end=DDE6`, `vars_end=E1FF`, `BGBUF=E100`; the accepted 2B layout was `QSQ=C200`, `code_end=DCE6`, `vars_end=E0FF`, so this first refactor crossed an alignment page and shifted the layout by exactly `0x100`. The production assertion itself was not changed or weakened.
- Recovery action taken next: shrink/repack the two-colour return implementation until the normal production build again satisfies the existing boundary assertion, then add the required assembled positive/rejection tests and old/bad-behavior proof.
- Compact repair checkpoint: removed a redundant pocket-count cap from the return helper (physical off-board scanning already bounds returns to nine) and removed an unreachable Due-underflow clamp; added the zero-byte `due_other_call` probe label and focused `tools/test_due_recovery.py` coverage, including a controlled old-behaviour fixture. At that checkpoint, execution evidence was still pending.
- Run 100 still failed at the unchanged production boundary assertion before focused tests could run. A temporary `pre_qsq` display was added immediately before the existing 256-byte alignment to measure the exact remaining byte deficit without changing the assertion or alignment.
- Run 101 confirmed the same production boundary failure; the normalizer strips source display directives, so that probe emitted nothing. The inert probe was removed. A temporary workflow measurement then used only a disposable normalized copy with its generated failure line neutralized, printed the boundary symbols, and still ran the untouched production build.
- Run 102 stopped in the temporary measurement step because the normalizer had already renamed the generated dot-prefixed failure token, so the exact string replacement missed it. Production was not reached. The disposable measurement was then changed to neutralize the generated failure line by its assertion text instead.
- Run 103 measurement succeeded and confirmed `QSQ=C300`, `code_end=DDE6`, `vars_end=E1FF`, `BGBUF=E100`; the untouched production build then failed at the same boundary assertion. A zero-byte `pre_qsq` label was then added immediately before the existing alignment so the next measurement could report the exact byte deficit.
- Run 104 measured `pre_qsq=C213`, proving the current refactor was exactly 19 bytes past the `C200` alignment boundary. The return helper was then repacked by keeping colour on the stack, keeping forced count in C, deferring `left[colour]` update until the scan completes, and using a compact 0/9 body-base reduction. This removed exactly 19 code bytes without changing the production boundary check. Temporary measurement scaffolding was removed; proof was pending the next workflow.
- Final evidence: clean-build run 105 passed. Both clean production builds were byte-identical; TZX validation reported ROM pilots 2824/2420, fast leaders 256/256, 855/1710 data pulses, 24831-byte game payload, and no pauses. All Phase-1, 2A, 2B, and 2C focused assembled checks passed, including the controlled old-behaviour fixture in `test_due_recovery.py`. Three cycle-level loads reached PC 32768; runtime four-seat/player flow, controls, points add/return/reset, sound loop, screen checks, and quit-to-BASIC all passed. Vocabulary gate passed. Emulator proof only.

## Fix group 2D — Session PTS by coin ownership
**Status: PASS**

- Affected files: `src/game.asm`, `src/carrom.asm`, `tools/test_session_pts.py`, workflow hook, ledger.
- Reproduction: current `stats_stroke` reads only mover-relative `rn`, mover-return `rgiven`, and mover pair `rA`; opponent-colour pockets therefore cannot credit the owning pair.
- First repair attempt: replace mover-only accounting with a per-colour helper driven by `rret[colour]`; map colour to owning logical pair through `white_pair`; score white and black independently. To preserve the C200 table boundary, the 66-byte helper replaces the old 69-byte routine, a 30-byte two-colour wrapper was placed after the aligned tables, and 31 bytes with no direct symbol references were removed.
- Focused assembled test added for opponent-colour credit, mixed-colour credit, return subtraction by colour, same-stroke pocket/return netting, underflow rejection, colour/pair remapping, bounded-counter overflow signalling, and a controlled old-behaviour fixture. At that point, execution evidence was pending.
- Run 106: both clean builds and every focused assembled check, including `session-PTS`, passed. Runtime acceptance then failed. Investigation found a new dependency-order defect in this checkpoint: `ord_f` is not dead storage; collision code accesses it indirectly as the fourth 20-byte array after `ord_x/ord_y/ord_id`. Removing it corrupted later runtime state. The runtime counter probe also still drove the retired mover-only `rgiven` interface.
- Repair: restore the full collision-array layout and all other removed scratch fields except the two genuinely retired Due scratch bytes, which are replaced in-place by dedicated `rret[2]` storage. Move the 40-byte two-colour/board-end accounting wrappers into the 64-byte unused tail of the aligned ROWLO page, so code size and variable boundary do not grow. Board-ending accounting explicitly zeroes dedicated return counts before scoring. Update the runtime counter probe to the per-colour interface and add a stale-return board-end rejection case. At that point, the rerun was still pending.
- Final evidence: clean-build run 107 passed. Both production builds and byte comparisons passed with the accepted 24831-byte game payload. `session-PTS` and all earlier focused assembled checks passed; three cycle-level loads reached PC 32768; runtime points changed live and add/return/reset checks passed; sound, controls, four-player flow, screen checks, and quit-to-BASIC passed; TZX timings/pilots/leaders/no-pause validation and vocabulary gate passed. Emulator proof only.
- Old/bad proof: `test_session_pts.py` replaces only the second-colour tail call in snapshot memory with a return; the opponent-colour credit then disappears, reproducing the old defect while the repaired program passes.

### Phase 2 striker/resolver matrix
**Status: PASS**

- Added assembled matrix coverage for striker alone, striker+own, striker+opponent, and striker+own+opponent, each with zero and one pre-existing mover Due. The cases provide enough previously pocketed mover coins to exercise physical repayment, verify Due accumulation/recovery, returned body colour, opponent retention, continuation/end-turn state, `left[]`, and final two-pair PTS.
- Added unavailable-Due rejection rows plus a combined Queen+striker+own+opponent+existing-Due row. Every case checks bounds, unique on-board coin centres, and score agreement with retained/returned bodies. At that point, execution evidence was pending.
- Final evidence: clean-build run 108 passed `resolver-matrix assembled checks` together with every earlier focused check. Both clean builds, deterministic TZX validation, three cycle-level loads, full runtime acceptance, quit-to-BASIC, and vocabulary gate all passed. The matrix covered all four striker rows with and without an existing mover Due, unavailable-Due rejection, and the combined Queen/striker/own/opponent/existing-Due case.

## Phase 2 gate

**Status: PASS**

- Current and earlier focused tests: PASS — authoritative run 109 passed player-map, Queen-history, pass-replay, extra-breaker, Queen-striker, Due-recovery, session-PTS, and resolver-matrix assembled checks.
- Production build: PASS — two clean Pasmo production builds completed in run 109.
- Validators: PASS — run 109 final TZX reported blocks 11/11/19/19, ROM pilots 2824/2420, fast leaders 256/256, data pulses 855/1710, 24831-byte game payload, and no pauses.
- Runtime acceptance: PASS — run 109 completed three cycle-level loads to PC 32768; four seats/logical players, turn flow, controls, live points, add/return/reset, groove/effects, phase/screen/loading checks, and quit-to-BASIC all passed. Emulator proof only.
- Two clean builds and byte comparison: PASS — game binary, TZX, and release ZIP comparisons passed in run 109.
- Restricted-vocabulary result: PASS — clean in run 109.
- Runner-state check immediately before checkpoint push: PASS — 0 queued, 0 running.
- Checkpoint push: PASS — `bcf99b572e6f801551a0d919d3a0aef939294666`.
- Authoritative workflow result: PASS — clean-build run 109 completed successfully.
- Workflow release-refresh commit: PASS — `f6c6ff4c6f6aa15dca29564a15adb74f7bba12dc`.
- Post-run runner state: PASS — 0 queued, 0 running.

# Phase 3

## Fix group 3A — Legal striker fallback
**Status: PASS**

- Affected files: `src/game.asm`, `src/tables.asm`, `tools/test_striker_fallback.py`, workflow hook, ledger.
- Reproduction: the second fallback tier ended at `.mid`, forced `plan_u=0`, called `place_xy`, and committed velocity without calling `strike_legal`; a coin overlapping the centre baseline could therefore receive an illegal striker placement.
- Repair: replace the unchecked centre commitment with `fallback_legal`, a deterministic exhaustive scan of half-pixel baseline centres -28..28. A legal point is doubled into `plan_u`; if every point is blocked, the turn is explicitly passed and carry prevents `PH_PLACE` from being committed. `set_velocity` now guarantees carry-clear on every successful plan.
- Layout: the fallback scanner is packed into ROWLO's existing alignment padding. The adjacent Phase-2 PTS wrapper is reduced equivalently using `LD BC,(rn)` plus a conditional swap, so the alignment and payload boundary remain unchanged.
- Focused assembled coverage: centre blocked/non-centre legal, centre as the only legal point, ordinary targetable fallback with finite velocity, every baseline point blocked with explicit pass/no velocity commitment, old-centre overlap rejection, and a controlled old-behaviour fixture. Execution evidence pending workflow.
- Final evidence: clean-build run 110 passed the striker-fallback assembled checks together with all Phase-1/2 focused checks. Both clean production builds reproduced byte-for-byte, final TZX validation retained the accepted pilots/leaders/data timings and zero pauses, three cycle-level loads reached PC 32768, full runtime/control/audio/counter checks passed, quit-to-BASIC passed, and the vocabulary gate was clean. Emulator proof only.

## Fix group 3B — Unbiased bounded random reduction
**Status: PASS**

- Affected files: `src/core.asm`, `src/game.asm`, `tools/test_random_bounds.py`, workflow hook, ledger.
- Reproduction: `rand_n` reduced every 0..127 source value modulo C, so divisors that do not divide 128 over-weighted low buckets.
- Repair in this checkpoint: compute `128 mod C`, reject the incomplete high tail, then reduce only accepted source values. The routine still takes nonzero C and preserves deterministic seeded behavior.
- Boundary packing: the unbiased routine is 11 bytes larger. Exactly 11 bytes are recovered before the fixed QSQ page boundary by looping the player-map validator, tail-jumping `draw_board`, removing the documented dead `recompute` load, using `xor a` for striker clearing, and folding the friction carry clear into `xor a`. No table, variable, or boundary invariant is moved.
- Focused assembled/static coverage added for divisors 4, 7, 9, 11, 13, and 24, a synthetic 0..127 source cycle, rejected-tail redraw, deterministic seeded repetition, range checks, equal accepted buckets, and the nonzero-divisor call-site precondition. Execution evidence pending workflow.
- Run 111 stopped at assembly because this Pasmo build does not accept the sign condition on a relative branch. The retry branch is changed to the supported absolute conditional jump. Its extra byte is recovered by tightening the player-map validator loop while preserving carry and the exact QSQ boundary.
- Run 112 built twice and all earlier focused checks passed, but the new random test stopped before executing because its source parser counted profile literals rather than profile bytes. The parser now extracts the four explicit jitter-radius fields directly; production code is unchanged.
- Run 113 again built twice and passed every earlier focused check. The new test then read the wrong simulator register slot for A, producing a false range failure at C=4. It now uses the simulator's exported A register index; production code is unchanged.
- Final evidence: clean-build run 114 passed `random-bounds assembled checks` and every earlier focused check. Both clean builds were byte-identical; final TZX validation retained ROM pilots 2824/2420, 256-pulse leaders, 855/1710 data timing, the 24831-byte payload, and no pauses. Three cycle-level loads, full runtime/control/audio/counter checks, quit-to-BASIC, and the vocabulary gate passed. Emulator proof only.

## Fix group 3C — Dependable production boundary failure
**Status: IN PROGRESS**

- Affected files: `build.py`, `tools/prepare_pasmo.py`, `tools/check_boundary.py`, `tools/test_boundary_guard.py`, workflow hook, ledger.
- Reproduction: the source invariant was translated to a dot-prefixed error token; earlier Phase-2 boundary failures proved this produced assembler syntax errors rather than a dependable explicit production guard.
- Repair in this checkpoint: retain `ASSERT vars_end < BGBUF` in source, strip only that source directive during deterministic Pasmo normalization, and immediately enforce the strict ordering from Pasmo's generated symbol file before any release packaging proceeds. Any other future source assertion is rejected by the normalizer until it has an explicit dependable guard.
- Focused production-path test added: verify the normal built symbols pass, then assemble disposable source copies whose variable tail is grown exactly to equality and one byte beyond; the same boundary checker invoked by `build.py` must fail nonzero for both. Execution evidence pending workflow.

## Fix group 3D — Subpixel-safe returned-coin placement
**Status: NOT STARTED**

## Phase 3 gate and final acceptance

**Status: NOT STARTED**

- Current and earlier focused tests: NOT RUN.
- Production build: NOT RUN.
- Validators: NOT RUN.
- Runtime acceptance: NOT RUN.
- Final TZX cold-load sequence: NOT RUN.
- Four-robot gameplay and controls: NOT RUN.
- Audio stability: NOT RUN.
- Zero-gap and 256-pulse acquisition repeatability: NOT RUN.
- Two clean builds and byte comparison: NOT RUN.
- Restricted-vocabulary result: NOT RUN.
- Documentation consistency: NOT RUN.
- Release ZIP contents: NOT RUN.
- Runner-state check immediately before checkpoint push: NOT RUN.
- Checkpoint push: NOT DONE.
- Authoritative workflow result: NOT RUN.
- Final runner-state check: NOT RUN.
- Final branch cleanliness: NOT RUN.
