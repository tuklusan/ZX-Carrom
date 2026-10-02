# Project rules

## Deliverables

Every accepted project deliverable must be committed under `dist/` on `main`.

For each accepted release, commit the final TAP, TZX, release ZIP, and recorded SHA-256 sums. The committed files must be the exact outputs from a fresh validated production build. Temporary job artifacts are copies only and do not satisfy this rule.

Do not declare a release complete while accepted deliverables exist only in job storage, a local worktree, or any other transient location.
