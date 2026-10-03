# ZX-Carrom review-fix runbook

## Purpose

This runbook turns the active findings in `scratch/zx-carrom-adversarial-review-final.md` into three ordered repair phases. Each phase is closed by focused positive tests, focused negative tests, the production build, runtime checks, reproducibility checks, and one clean workflow run. No later phase may begin until the prior phase gate is fully green.

The active review ledger is eight major findings plus two advisories. The withdrawn former MAJOR 5 is not work and must not be reintroduced unless new evidence changes the review.

## Global execution rules

1. Work on `main`. Do not rewrite published history.
2. Before every push, confirm that no repository workflow is queued or running. Push only one phase checkpoint at a time. Wait for that run to finish before the next push.
3. Make tests part of the same phase as the fixes they protect. A phase is not complete merely because it assembles.
4. Every repaired finding needs at least one positive regression case and at least one negative or rejection case that proves the bad state is not accepted.
5. Prefer machine-level checks against the assembled program. Extend the existing simulator harness or add a small deterministic harness that loads the built snapshot, writes controlled state through symbols, calls the target routine, and asserts memory/register results.
6. Do not weaken an existing validator or runtime acceptance check. New checks are additive.
7. Use `python3 build.py` as the normal production entry point. Production assembly remains Pasmo.
8. After any change that can affect payload size or addresses, rerun the boundary check and final tape validation.
9. At each phase gate, preserve the sole release tape as `dist/carrom_fast.tzx`; no normal-speed tape or WAV becomes a release output.
10. If a focused test exposes a new defect, stop that phase, record it, fix it in dependency order, and restart the phase gate from the first focused test.

## Test-harness rule

Add or extend deterministic focused checks under `tools/`. The checks must exercise assembled routines or a loaded assembled snapshot, not merely duplicate the intended rules in a separate model. It is acceptable to factor the existing routine-call helper from `tools/sim.py` into reusable test support.

For each finding below, the negative case means an intentionally difficult or invalid input/state that the corrected program must reject or handle safely. The negative case itself passes when the program refuses the bad outcome.

---

# Phase 1 — Correct persistent state before rule-resolution changes

## Fix group 1A — Logical player identity and seat rotation

**Finding:** MAJOR 4 — robot profiles are tied to physical seats instead of logical players.

### Change

- Add a four-entry logical-player-to-seat mapping, or an equivalent explicit mapping with the same observable behavior.
- Route displayed profile names and robot profile selection through logical player identity rather than direct `seat` indexing.
- Apply the required doubles side change at the game transition while keeping each logical player's profile attached to that player.
- Keep `seat` as the physical N/E/S/W turn position; do not overload it with player identity.

### Positive tests

- At a fresh match, verify four distinct logical players map one-to-one onto the four physical seats.
- After the required side-change transition, verify each logical player has moved to the correct physical seat while retaining the same profile/name.
- Across the next game transition, verify the expected breaker and colour-pair relationship is derived from the rotated mapping rather than from profile identity.
- Run long autonomous play and confirm all four logical players still take turns.

### Negative tests

- Force a physical-seat change without changing logical identity and verify the displayed/planner profile does not silently become the profile formerly tied to that seat.
- Exercise two successive game transitions and reject any duplicate or missing logical-player mapping.

## Fix group 1B — Queen-eligibility history by coin colour

**Finding:** MAJOR 7 — Queen eligibility history is too narrowly recorded.

### Change

- Treat `had[colour]` as historical evidence that at least one coin of that colour has been pocketed during the current board.
- Set it from pocket events by coin colour, regardless of which player made the pocket.
- Do not clear that historical fact merely because the coin is later returned as a Due or striker consequence.
- Reset it only with new-board state.

### Positive tests

- When side A pockets a side-B coin, verify `had[B]` becomes true.
- When a player pockets an own coin with the striker and that coin is returned, verify the colour's history still becomes true.
- Verify Queen targeting becomes eligible once the colour has the required history and has no blocking Due.

### Negative tests

- With no coin of a colour ever pocketed on the board, verify `had[colour]` remains false.
- Returning a coin that was never newly pocketed in the tested stroke must not fabricate history for the other colour.
- A pending Due must still block Queen targeting even when `had[colour]` is true.

## Fix group 1C — Consecutive-pass state

**Finding:** MAJOR 3 — consecutive-pass replay bookkeeping cannot perform its intended recovery.

### Change

- Replace the present use of `consecutive` with state that counts actual pass/no-progress events rather than successful continuation strokes.
- Define the replay threshold from an existing authoritative rule/design source before coding it. The current reviewed source contains no threshold test, so do not invent a number silently.
- Reset the streak only on the rule/design-defined progress event.
- Route threshold completion to one clean board replay/recovery path with all board state reset consistently.

### Positive tests

- Feed pass events up to one below the chosen threshold and verify no replay occurs.
- Feed the threshold pass event and verify exactly one board replay/recovery occurs.
- Verify a qualifying progress event resets the pass streak.
- Verify ordinary own-coin continuation does not increment a pass streak.

### Negative tests

- Repeated continuation strokes must never trigger the pass-replay threshold.
- A single pass followed by progress must not leave stale streak state that later causes an early replay.
- Restart/new-board setup must clear the streak.

## Phase 1 gate — mandatory before Phase 2

Phase 1 is green only when all of the following are true:

- All focused positive and negative checks for 1A, 1B, and 1C pass against the assembled program.
- At least one test for each group is demonstrated to fail against the pre-fix behavior or an equivalent controlled defect fixture, proving the test is capable of catching the reviewed bug.
- `python3 build.py` succeeds with Pasmo and all existing deterministic tape validators remain green.
- Existing runtime acceptance still shows four autonomous players, advancing turns, stable physics, live music, working controls, restart, and clean quit-to-BASIC.
- Two clean production builds from the same revision produce byte-identical game binary, TZX, and release ZIP.
- The restricted-vocabulary gate is clean.
- No workflow is already queued/running when the phase checkpoint is pushed.
- Exactly one clean workflow run for the phase checkpoint completes successfully before any Phase 2 push.

---

# Phase 2 — Repair rule resolution, returns, and public counters

Phase 2 may start only after the Phase 1 gate is fully green.

## Fix group 2A — Extra-board breaker selection

**Finding:** MAJOR 1 — extra-board break uses ordinary rotation instead of a fresh toss.

### Change

- Add explicit extra-board state at the tied eighth-board transition.
- Select the extra-board breaker by a fresh 0..3 toss instead of `boards_in_game + games_played + break_off` rotation.
- Convert that selected logical player to the current physical seat through the Phase 1 mapping.
- Derive the white pair from the selected break seat exactly as normal board setup does.

### Positive tests

- Force an eighth-board tie, inject each toss result 0..3 in turn, and verify the selected logical breaker and physical seat match that toss under the current mapping.
- Verify the white pair matches the actual breaker seat.
- Verify normal non-extra boards still use ordinary rotation.

### Negative tests

- Choose board/game counters whose old rotation formula would pick a different seat from the injected toss; verify the toss wins.
- A normal board must not consume or use extra-board toss state.

## Fix group 2B — Queen + own coin + striker continuation

**Finding:** MAJOR 6 — Queen + own coin + striker continuation is wrong when all nine own coins began on the board.

### Change

- Separate the Queen+striker/no-own-coin case from Queen+own-coin+striker.
- For Queen+own-coin+striker, return the Queen, the own pocketed coin(s), and the required Due, then continue play even when `rbefore == 9`.
- Keep return counts, `left[]`, `dues[]`, Queen state, and continuation state synchronized.

### Positive tests

- Set `rS=1`, `rQ=1`, `rn>0`, `rbefore=9` and verify Queen return, required own-colour returns, correct Due state, and `rcont=1`.
- Repeat with `rbefore<9` and verify the same rule family remains correct.

### Negative tests

- Queen+striker with no own coin must not inherit the continuation behavior of Queen+own-coin+striker.
- A failed return placement must not leave `left[]`, Queen state, or Due state claiming a body was returned when it was not physically placed.

## Fix group 2C — Two-colour Due recovery

**Finding:** MAJOR 8 — outstanding Due for the non-moving colour is not recovered when it becomes available.

### Change

- Resolve newly available Due obligations for both colours after pocket counts are established.
- Keep four concepts separate: coin colour, moving player, who is entitled to place a returned coin, and physical body placement.
- Produce per-colour returned-coin counts for the score/stat update in group 2D.

### Positive tests

- Give colour B one outstanding Due; have side A pocket a B coin; verify one B coin is returned and B's Due decreases appropriately.
- Repeat with obligations on both colours and a stroke that makes both colours available; verify each colour is resolved independently.
- Verify returned body IDs belong to the colour whose obligation is being paid.

### Negative tests

- If colour B owes a Due but no B coin is available in a pocket, verify no on-board B coin is removed and the Due remains outstanding.
- Paying B's Due must not decrement A's Due or return an A coin.
- The return loop must never increase `left[colour]` above nine.

## Fix group 2D — Session PTS by coin ownership

**Finding:** MAJOR 9 — session PTS ignores opponent-colour coins pocketed by the mover.

### Change

- Compute score deltas per coin colour for both pairs, independent of who struck the shot.
- Add points for each coin that remains pocketed after rule resolution.
- Subtract points for each returned coin from that coin colour's pair.
- Consume the per-colour return counts from group 2C so board state and public counters cannot diverge.
- Preserve the current bounded-counter behavior: if any bounded public counter would overflow its display limit, reset the public counter group as designed.

### Positive tests

- Side A pockets a B coin and it remains off-board: B pair PTS increases by one.
- Side A pockets one A and one B coin, both retained: each pair increases by one.
- A returned B coin decreases B pair PTS, regardless of who caused the return.
- Pocket then return of the same colour in the same resolved stroke produces the correct net change.
- Existing add, return, and bounded-counter reset tests remain green.

### Negative tests

- An opponent-colour pocket must not credit the moving pair merely because that pair struck the shot.
- A coin that is returned in the same resolution must not remain counted as permanently pocketed.
- Score subtraction must not underflow into a large displayed value.

## Phase 2 gate — mandatory before Phase 3

Phase 2 is green only when all of the following are true:

- Every focused positive and negative check for 2A through 2D passes against the assembled program.
- At least one test for each group is shown to catch the pre-fix behavior or an equivalent controlled defect fixture.
- A combined resolver matrix covers simultaneous Queen, striker, own-colour, opponent-colour, existing-Due, and return combinations used by these fixes, with invariants checked after every case: `0 <= left[colour] <= 9`, no duplicate on-board body, returned-body colour is correct, Due counts are non-negative, and score deltas agree with retained pocketed bodies.
- `python3 build.py`, deterministic tape validation, runtime acceptance, and quit-to-BASIC all pass.
- Live play demonstrates changing PTS when coins are pocketed and correct PTS decreases when coins are returned.
- Two clean production builds from the same revision are byte-identical for game binary, TZX, and release ZIP.
- The restricted-vocabulary gate is clean.
- No workflow is queued/running when the phase checkpoint is pushed.
- Exactly one clean workflow run for the phase checkpoint completes successfully before any Phase 3 push.

---

# Phase 3 — Remove unsafe fallback and harden production guards

Phase 3 may start only after the Phase 2 gate is fully green.

## Fix group 3A — Legal striker fallback

**Finding:** MAJOR 2 — fallback can commit an illegal centre striker placement.

### Change

- Remove the unchecked `.mid` commitment of `plan_u=0`.
- Search the legal baseline deterministically for a valid fallback position, or take an explicit no-legal-placement/pass path when none exists.
- Every chosen striker centre must pass `strike_legal` before `place_xy` and velocity commitment.

### Positive tests

- Block centre while leaving another baseline position legal; verify fallback chooses a legal non-centre position.
- Leave centre legal; verify centre remains a permitted fallback when appropriate.
- Confirm normal targetable fallback shots still produce legal striker positions and finite velocity.

### Negative tests

- Make every permitted baseline position illegal; verify no illegal shot is committed and the explicit no-placement path is taken.
- Place a coin so the old centre fallback overlaps it; verify centre is rejected.

## Fix group 3B — Unbiased bounded random reduction

**Finding:** ADVISORY 1 — `rand_n` uses biased modulo reduction.

### Change

- Replace simple reduction with rejection sampling over the routine's 0..127 source range.
- For divisor `C`, accept only source values below `floor(128/C)*C`, then reduce to 0..C-1.
- Preserve caller-visible bounds. The same seed must remain repeatable after the change, but the exact old random sequence need not be preserved because rejection sampling can consume extra source values.

### Positive tests

- For representative divisors used by the game, verify every result is in range.
- Feed a complete synthetic 0..127 source cycle and verify each accepted result bucket has equal count after rejected tail values are excluded.
- Exercise every current call-site divisor: 4, 7, 9, 11, 13, and 24.

### Negative tests

- Force source values in the rejected tail and verify the routine draws again rather than returning a biased bucket.
- Divisor zero must be impossible at all call sites; add a static/runtime assertion for that precondition rather than defining accidental behavior.

## Fix group 3C — Dependable production boundary failure

**Finding:** ADVISORY 2 — the translated boundary assertion is not a dependable production hard stop.

### Change

- Keep the source boundary invariant that variables must end below `BGBUF`.
- Enforce it with a Pasmo-supported mechanism that fails the production build reliably, or with an explicit post-assembly address check driven by generated symbols.
- Do not rely on translated dot-local error syntax whose behavior is uncertain.

### Positive tests

- Build the normal source and verify the boundary check reports the real safe ordering.
- Verify the final assembled payload still ends below `BGBUF`.

### Negative tests

- In a disposable test copy, deliberately grow the variable area across `BGBUF` and verify the production check fails non-zero.
- Deliberately set equality at the forbidden boundary and verify it also fails if the invariant remains strict `<`.
- Restore the source and rerun the clean build; no negative-test mutation may remain tracked.

## Phase 3 and final acceptance gate

Phase 3 is complete only when all of the following are true:

- Every focused positive and negative check for 3A through 3C passes against the assembled program/build path.
- At least one test for each group is shown to catch the pre-fix behavior or an equivalent controlled defect fixture.
- All focused tests from Phases 1 and 2 are rerun and remain green; no phase may rely only on its newest tests.
- `python3 build.py` creates fresh release outputs with Pasmo.
- Independent TZX parsing proves ROM bootstrap pilot counts of 2824 then 2420 pulses, a total fast leader of 256 pulses at 1710 T-states even when the leader spans multiple `0x13` pulse blocks, turbo data timing of 855/1710 T-states, no explicit pause blocks, every block pause equal to 0 ms, turbo SCREEN$ payload before the turbo game payload, load addresses, entry point, framing, and integrity fields.
- The loader/bootstrap is freshly rebuilt from current source with Pasmo, preserves the adapted loader semantics and attribution, and does not rely on a stale bootstrap artifact.
- Cycle-level cold-load/runtime acceptance from the standard 48K ROM path proves the loading screen appears before game loading, the game loads from the same TZX, the 256-pulse leader is acquired reliably, zero-gap SCREEN$-to-game transition is reliable, the playable board is reached, four robots operate, turns progress, physics remains stable, live music continues and loops, effects do not corrupt state, M/SPACE/F/R/Q work, and repeated play remains stable. The proof must exercise the final `dist/carrom_fast.tzx` with accurate tape playback; an expanded/helper copy or instant-load shortcut may assist diagnosis but cannot be the sole acceptance proof.
- Game-quality acceptance rejects stuck robots, endless turns, impossible board states, broken public counters, visible garbage, frozen controls, sound lockups, loader races, loading-screen corruption, and recurring timing failures.
- If the final proof is emulator-only, documentation states that plainly and does not claim real-hardware proof.
- Two clean production builds from the same revision produce byte-identical game binary, TZX, and final ZIP.
- The workflow records and verifies the release checksum set for the accepted outputs.
- Final ZIP contains source plus the accepted TZX and no normal-speed tape or WAV release file.
- Documentation matches the resulting behavior, loader structure, timings, controls, audio provenance/architecture, build method, tested runtime status, and accepted release artifact.
- The restricted-vocabulary gate is clean.
- Repository source state is clean apart from accepted release outputs produced by the workflow.
- No workflow is queued/running when the final phase checkpoint is pushed.
- Exactly one authoritative clean workflow run completes successfully for the final checkpoint.

## Completion rule

Do not mark the review findings closed one by one merely because code was edited. Mark a finding closed only when its phase's focused positive tests, negative tests, full phase gate, and authoritative workflow run have all passed. If a later phase invalidates an earlier proof, reopen the affected finding and rerun every dependent gate.