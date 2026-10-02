# Historical comparison artifacts

The handoff package contained three historical tape images used while repairing the build pipeline. They are intentionally **not** release products and are not kept in the final source tree, so stale tapes cannot be mistaken for accepted output.

Their SHA-256 values, for provenance/comparison with the handoff package, were:

- `carrom_previous.tap` — `235c2c279acf4f0aca77def705ded87c95ed7f7696aa7e2ac435d8207e10a358`
- `carrom_fast_previous_repacked.tzx` — `6e6b18650d555b0b714a2105ce1acda9c4c5e861518115e642b34f0f3307f520`
- `zqloader_carrom_previous.tap` — `2abf34ff23ecb25fae82c95ed4866a9036570df623b70f0f9a69982ea79361e8`

The first two came from the earlier Carrom build. The third is the historical ZQLoader bootstrap that was formerly used as a production input. The current build assembles the loader bootstrap fresh with Pasmo instead.
