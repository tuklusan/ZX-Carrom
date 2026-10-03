# ZX-Carrom adversarial assembler review — final report

## Scope and method

Authority was the source carried inside the accepted clean-build run 94 release artifact, not a newer repository checkout. The assembler corpus contains 11 files and 8,276 lines.

The requested protocol was followed conservatively: each qualifying pass used a newly extracted copy, Step 1 re-read all assembler lines from disk with clipped displays reopened in smaller numbered ranges, Step 2 performed a semantic dry run, and any suspected new defect invalidated the pass. Passes 10, 11, and 12 are the three successive qualifying clean cycles.

This is an isolated adversarial review. It is not independent human sign-off.

## Final gate

- Pass 10: full fresh-copy scan complete; semantic dry run found no new defect. Clean cycle 1/3.
- Pass 11: full fresh-copy scan complete; semantic dry run found no new defect. Clean cycle 2/3.
- Pass 12: full fresh-copy scan complete; semantic dry run found no new defect. Clean cycle 3/3.

Final active ledger: 0 blocker, 0 critical, 8 major, 2 advisory.

One previously logged major was withdrawn during final reconciliation because the governing turn rule allows continuation when the same proper stroke pockets both an own coin and an opponent coin. The implementation's continuation in that case is therefore correct.

## Active findings

### MAJOR 1 — Extra-board break uses ordinary rotation instead of a fresh toss

Evidence: `src/game.asm` lines 109-120 and 1380-1397.

When an eighth-board tie reaches an extra board, `setup_board` derives the breaker from `boards_in_game + games_played + break_off`. There is no fresh toss before the extra board.

Impact: the extra-board breaker is deterministic when the rules require a new toss for break choice.

Recommended fix: add an explicit extra-board state. On the tie after board eight, choose a fresh random breaker 0..3, then derive the white pair from that breaker. Keep ordinary rotation for normal boards.

### MAJOR 2 — Fallback can commit an illegal centre striker placement

Evidence: `src/game.asm` lines 2889-2971, especially 2952-2959 versus 2997-2999.

Normal fallback candidates call `strike_legal`. If no candidate survives, `.mid` forces `plan_u = 0` and proceeds without validating that centre placement.

Impact: the robot can plan a stroke from a striker position that overlaps a coin or otherwise violates the same placement test used for normal candidates.

Recommended fix: exhaustively search the legal baseline for a fallback position, or add an explicit no-legal-placement/pass path. Never commit the centre position without `strike_legal` succeeding.

### MAJOR 3 — Consecutive-pass replay bookkeeping cannot perform its intended recovery

Evidence: `src/game.asm` lines 950-990 plus the complete state-machine review.

`consecutive` increments when the same player continues, and `advance_seat` clears it whenever the turn passes. No threshold test exists that can recognize consecutive pass events and trigger the intended board replay/recovery path.

Impact: the safety mechanism cannot recover from the class of repeated no-progress turn sequences it appears intended to track.

Recommended fix: track actual pass events, reset only on the rule/design-defined progress event, test the chosen threshold, and route that threshold to a clean board replay path.

### MAJOR 4 — Robot profiles are tied to physical seats instead of logical players

Evidence: `src/game.asm` lines 1746-1801 and the match-transition state machine.

Both the displayed profile and planner profile are selected directly from `seat`. There is no logical-player-to-seat map, so required doubles side changes cannot move the same player/profile to the next seat.

Impact: after a game transition, physical seats keep their personalities instead of the players changing sides while retaining their identities.

Recommended fix: introduce a four-entry logical-player/seat map. Select names and planner profiles through that map, and rotate the map at the required doubles side-change transition.

### MAJOR 6 — Queen + own coin + striker continuation is wrong when all nine own coins began on the board

Evidence: `src/game.asm` lines 703-721.

For a proper stroke pocketing Queen, one or more own coins, and striker, the resolver marks the Queen for return. It then forces no continuation whenever `rbefore == 9`.

Impact: the fresh/full-set version of this combination ends the turn even though the Queen, own coin(s), and Due are to be returned and play is to continue.

Recommended fix: distinguish Queen+striker with no own coin from Queen+own-coin+striker. The latter must continue after the required returns, including when the side began the stroke with all nine coins on the board.

### MAJOR 7 — Queen eligibility history is too narrowly recorded

Evidence: `src/game.asm` lines 655-660 and 776-788; robot Queen targeting at 1883-1902.

`had[colour]` is used as persistent Queen-eligibility history, but it is set only when the moving side pockets its own coin without the striker. It is not set when that colour's coin is pocketed by the opponent, and it is also skipped when an own coin was pocketed with the striker and subsequently returned.

Impact: a side can remain incorrectly barred from targeting the Queen even though a coin of that colour has already been pocketed during the board.

Recommended fix: update the history from coin-colour pocket events, independent of who made the stroke and independent of a later Due return. Keep current board occupancy (`left`) separate from historical Queen eligibility.

### MAJOR 8 — Outstanding Due for the non-moving colour is not recovered when it becomes available

Evidence: `src/game.asm` lines 813-905.

The stroke can reduce `left[]` for both colours, but the Due recovery block indexes `dues[]`, `left[]`, and returned bodies only through `rcA`, the mover's colour.

Impact: if colour B owes a Due and colour A pockets a B coin, that newly available B coin is not recovered against B's outstanding obligation.

Recommended fix: after pocket counts are established, process newly available outstanding obligations for both colours. Keep colour ownership, who is entitled to place, physical placement, and score/stat updates as separate concerns.

### MAJOR 9 — Session PTS ignores opponent-colour coins pocketed by the mover

Evidence: `src/carrom.asm` around `score`; `src/game.asm` lines 1487-1539.

`stats_stroke` updates only the moving pair, using `rn` and `rgiven`. It does not apply `rm` to the beneficiary pair.

Impact: when a player pockets an opponent-colour coin that remains off the board, the public PTS for that coin's owning pair can fail to increase. This is consistent with the observed score counter problem. Return events can likewise desynchronize the display unless handled by colour.

Recommended fix: compute session-stat deltas per coin colour for both pairs, independent of the striker/player who made the stroke. Returned coins must subtract from the same colour's PTS. The two-colour Due fix should expose per-colour return counts so the board and public counters remain synchronized.

### ADVISORY 1 — `rand_n` uses biased modulo reduction

Evidence: `src/core.asm` lines 348-356.

The routine masks to 0..127 and repeatedly subtracts the divisor. For divisors that do not divide 128 evenly, some results occur more often than others.

Recommended fix: use rejection sampling below `floor(128/C) * C`, then reduce.

### ADVISORY 2 — The translated boundary assertion is not a dependable production hard stop

Evidence: `src/carrom.asm` line 684 and the production translation logic previously reviewed.

The accepted layout itself is safe: `code_end = $DCE6`, `vars_end = $E0F9`, the last variable byte is `$E0F8`, `BGBUF = $E100`, leaving seven bytes. The weakness is enforcement if the layout later grows.

Recommended fix: use a production-supported hard failure that cannot be neutralized by local-label normalization, or add an explicit post-assembly address check with a negative test.

## Withdrawn finding

### Former MAJOR 5 — opponent-colour coin in the same proper stroke as an own coin

This finding is withdrawn. The resolver's ordinary no-striker path calls `n_cont`, which continues when `rn > 0` even if `rm > 0`. That matches the governing turn rule: a proper stroke continues when the player pockets an own coin, and the rules also expressly preserve continuation in the striker+own+opponent combination.

No code change is recommended for this specific case.

## Areas rechecked without a new finding

The final semantic dry run rechecked loader entry and return-to-BASIC stack restoration; interrupt mode setup and restoration; stack and memory ownership; screen buffer boundaries; renderer/table indexing; collision and pocket event ordering; fixed-point helpers and their caller preconditions; Queen state transitions; Due recovery ordering; board/game/match transitions; robot target and fallback planning; message-buffer bounds; generated song pattern and note-table bounds; live interrupt music register preservation; sound-effect interaction with the live groove; pause, fast mode, restart, sound cycling, and quit controls.

Generated live-song data remains internally bounded: all live pattern note indices are within the 19-entry note table, and the 32-pattern loop at six 50 Hz frames per step is 3,072 frames, about 61.44 seconds.

No additional blocker, critical, major, or advisory defect was promoted during Pass 12 Step 2.

## Conclusion

The requested three-clean-cycle review gate is satisfied by Passes 10, 11, and 12. The review is complete against the accepted run-94 assembler corpus.

The source has 8 active major findings and 2 advisories to repair before treating the reviewed assembler as defect-free. No source edits were made during this audit.