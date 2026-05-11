# Changelog examples — drafted from real merged MRs

Concrete illustrations of the rules in `conventions.md` → **Changelog**.
Each entry below was reverse-engineered from a recently-merged MR on
`gitlab.com/tezos/tezos`, picked to cover the Etherlink kernel, the
Tezos X kernel, and the Octez EVM node. The wording is what *I* would
have written into the appropriate `etherlink/CHANGES_*.md` file at MR
time. Some of these entries already exist verbatim in the repo (e.g.
`!21791`, `!21792`, `!21807`); others (`!21814`, `!21817`, `!21820`,
`!21824`) had no entry at merge time and are written from scratch here
to show the gap.

Source data: `glab mr list -R tezos/tezos -M --per-page 50` taken on
2026-05-07, filtered to titles matching `Etherlink`, `EVM Node`,
`TezosX`, or `Tezos X`.

---

## How each example maps to the four rules

| Rule (from `conventions.md`)                     | Illustrated by                                                              |
|--------------------------------------------------|-----------------------------------------------------------------------------|
| Link to the MR                                   | every entry — `(!21814)` style at end of bullet                             |
| Descriptive (user-perspective, not file-level)   | `!21797` (indexer impact), `!21792` (Blockscout symptom), `!21786` (RPC)    |
| Flag breaking changes explicitly                 | `!21791` (cap diverges from L1), `!21792` (storage V55 migration)           |
| Cross-component version constraints at the header | "Release kernel 0.3" + "EVM Node 0.58" headers below                        |

---

## `etherlink/CHANGES_TEZOSX.md` — additions to the **Unreleased** section

### Native atomic composability

- Persist `original_evm_source` across re-entrant EVM frames so every
  CRAC issued from a Michelson `call_evm` callback recovers
  `alias(EOA)` regardless of nesting depth. The EOA identity used to
  live on the per-execution `Journal` and was reset to `None` every
  time the EVM runtime was re-entered, causing nested CRACs to record
  `tx.origin = alias(intermediate_Mich)` instead of the original EOA
  and to poison the alias cache with a spurious alias-of-alias entry.
  The field now lives on `EvmJournal` (transaction-scoped) and keeps
  first-set-wins semantics. (!21817, L2-1303)

- Place failed re-entrant inner CRACs in DFS execution order on the
  merged synthetic Michelson manager-op, matching the order of
  successful re-entrant CRACs. Previously
  `drain_reentrant_crac_ops` only drained `pending_crac_receipts`, so
  a failed inner CRAC kept its (smaller, push-time) sequence number
  and surfaced *ahead* of its outer parent's transfer. The receipt
  layout used to read `[failed inner C2 / outer C1 / …]`; it now
  reads `[outer C1 / inner C2 …]`. (!21814, L2-1300)

- Surface user `EMIT` events from re-entrant inner Michelson CRACs on
  the synthetic CRAC transaction receipt. Events emitted by a
  Michelson contract reached through a nested cross-runtime call
  (EVM → Mich → EVM → Mich within one EVM transaction) used to be
  silently discarded, breaking parity for Michelson-side event
  indexers. (!21807, L2-1301)

- Surface inner `LOG0..LOG4` and the precompile's `CracReceived` log
  on the synthetic CRAC transaction receipt produced by Michelson
  `%call_evm`. Pre-fix, only `CracIdEvent` survived because
  `commit_evm_journal_from_external` ran *before*
  `extract_cross_runtime_effects` and `JournalInner::finalize` had
  already cleared `inner.logs`. Restores indexer parity (subgraphs,
  on-chain analytics, ERC-1155 wallet trackers) between
  EOA-originated and Michelson-originated EVM activity. (!21797)

- Record native classification on freshly-originated KT1 contracts.
  Adds a default-no-op `record_native_origin` hook on the `Context`
  trait, overridden by `TezosRuntimeContext` to write the native
  variant of `Origin` at the KT1 origin sibling path via
  `set_origin_at`, called from `originate_smart_contract`. Closes
  the third native observation point of the transitive
  address-translation feature; protocol code shared with Tezlink
  stays decoupled from Tezos X storage layout. (!21824)

- Record native classification on EVM-side accounts (signer or
  freshly-deployed contract) and on Tezos implicit accounts at reveal
  time. EVM `update_account` marks the account native when the nonce
  strictly increases or the code hash transitions from empty to a
  non-alias non-empty hash; Tezos `set_manager_public_key` marks
  the implicit account via `set_origin_for_implicit`. KT1 origination
  is handled separately in `!21824`. (!21820)

- **Breaking change (parametric constants):** raise the Michelson
  runtime `hard_gas_limit_per_operation` and `hard_gas_limit_per_block`
  from 1,040,000 to 3,000,000 gas units (3,000,000,000 milligas) to
  match the EVM 30M-gas per-transaction cap. These two parametric
  constants now **diverge from the L1 mainnet defaults** (which both
  stay at 1,040,000): a Michelson operation accepted by Tezos X may
  exceed the gas budget the same operation would be allowed on L1.
  Without this change, an EVM transaction reaching the cross-runtime
  precompile with more than ~10.4M gas remaining forwarded an
  oversized `X-Tezos-Gas-Limit` and was rejected by the Michelson
  runtime, surfacing as a misleading EVM out-of-gas. (!21791, L2-1295)

- **Breaking change (storage migration V55):** stop persisting a
  `U256::MAX` balance for the internal `TEZOSX_CALLER_ADDRESS`
  (`0x7e205800…01`) used by `generate_alias`. The internal call uses
  `gas_price = 0` and `value = 0`, so the funding was unnecessary in
  the first place; only the manual `set_info_without_code` write was
  persisting (the surrounding `CrossRuntime` `run_transaction` never
  commits the EVM journal), leaking a visible huge balance on
  Blockscout. The new V55 migration deletes the residue on TezosX
  networks where it has already been written (e.g. Previewnet);
  reads of the account fall back to `AccountInfo::default()` (balance
  0, nonce 0, empty code) afterwards. (!21792, L2-1296)

### Internals

- Move the EVM 30M-gas per-tx cap and its Michelson 3,000,000,000-
  milligas mirror into a new leaf crate
  `etherlink/kernel_latest/tezosx-constants` so the kernel and
  `tezos_execution` derive both caps from the same source of truth.
  Pure refactor — no behavior change — but removes the two-place
  hard-coding that re-introduced the cross-runtime gas mismatch
  fixed in `!21791` if the constants ever drifted. (!21806)

---

## `etherlink/CHANGES_KERNEL.md` — new release block for kernel 0.3

This format demonstrates the **version-level cross-component
constraint** (rule 4): the peer-version note belongs at the release
header, not buried in a bullet, so operators and releasers can gate
upgrades on it without reading every line.

```markdown
### 0.3 (<commit-sha>)

This release of the Tezos X kernel rebuilds on top of the latest
re-entrant CRAC + native-classification work. Operators upgrading
from 0.2 should be aware of the points below.

**This kernel requires the Octez EVM node version 0.58 or higher.**
Older EVM-node versions cannot decode the new synthetic CRAC receipt
log layout (`!21797`, `!21807`) and will report empty logs on cross-
runtime transactions.

**Storage version 55** — the kernel auto-migrates from V54 on first
boot. Migration is restricted to TezosX networks (`enable_tezos_runtime
== true`) and only deletes the legacy
`TEZOSX_CALLER_ADDRESS` `U256::MAX` residue (`!21792`). No durable
data is rewritten outside that one path; downgrade to 0.2 is **not**
supported because the deleted account info cannot be restored.

**Parametric constants diverge from L1 mainnet** — the Michelson
runtime now accepts up to 3,000,000 gas per operation (vs.
1,040,000 on L1, see `!21791`). Tooling that lifts L1 operations
into Tezos X without re-validation may now accept operations that L1
would reject; tooling that lifts Tezos X operations down to L1 must
re-check `gas_limit` against the L1 cap.

(Then the usual sub-sections — Native atomic composability,
Internals, Breaking changes — referencing the same MRs as
`CHANGES_TEZOSX.md` above. Released MR for this version: !21830.)
```

---

## `etherlink/CHANGES_NODE.md` — additions to the **Unreleased** section

### RPCs changes

- Add an optional `block` parameter to the `tez_kernelVersion` and
  `tez_kernelRootHash` JSON-RPC methods, so callers can query the
  kernel version and kernel root hash at any historical block.
  Omitting the parameter preserves the previous behavior (returns the
  value at `latest`); no breaking change for existing clients.
  (!21786)

- Include `injectTezlinkOperation` in the list of supported EVM
  methods reported by the RPC node. (!21785)

### Experimental features changes

- Add a `compact_receipt_encoding` feature flag (off by default).
  When enabled, the EVM node serializes transaction receipts using
  the new compact encoding, reducing on-disk receipt size for nodes
  with large historical state. The flag is experimental: the
  encoding is subject to change without deprecation and an
  experimental-feature-aware `octez-evm-node check config` should
  be used to validate the configuration after upgrade. (!21761)

---

## `etherlink/CHANGES_NODE.md` — new release block for EVM Node 0.58

```markdown
## Version 0.58 (2026-05-06)

This release adds support for kernel 0.3 (`!21830`) on Tezos X
networks (Previewnet and the upcoming testnets) and ships the new
historical-block kernel version RPC.

**Compatibility:** EVM Node 0.58 is the minimum version required to
talk to a kernel 0.3 rollup. It is fully backward-compatible with
kernels 0.2 and 0.1: feature gating uses runtime probes, so the same
binary serves Mainnet (Etherlink kernel 6.x), Tezos X Previewnet
(kernel 0.2 → 0.3 after activation), and the local sandbox.

**No store migration** — the EVM-node store version is unchanged
from 0.57 (version 24), so downgrading to 0.57 is supported.

(Then the usual sub-sections, MR for the release: !21828.)
```

---

## Comparison with what is actually in the repo

Snapshot taken from `master` on 2026-05-07. For each MR a drafted
entry exists for above, this section shows what (if anything) is
already committed in `etherlink/CHANGES_*.md` and a short note on the
delta. Inserted to make the convention concrete: where the existing
entry already follows it, my draft converges on the same wording;
where it does not, the gap is the lesson.

### `!21791` — raise hard gas limit to match EVM per-tx cap

> **Already in `etherlink/CHANGES_TEZOSX.md` (Unreleased → Native
> atomic composability):**
>
> > Raise the Michelson runtime `hard_gas_limit_per_operation` and
> > `hard_gas_limit_per_block` from 1,040,000 to 3,000,000 gas units
> > (i.e. 3,000,000,000 milligas) to match the EVM 30M-gas
> > per-transaction cap. These two parametric constants now diverge
> > from the L1 mainnet defaults (which both stay at 1,040,000), so a
> > Michelson operation accepted by Tezos X may exceed the gas budget
> > the same operation would be allowed on L1. Without this change,
> > an EVM transaction reaching the cross-runtime precompile with
> > more than ~10.4M gas remaining would forward an oversized
> > `X-Tezos-Gas-Limit` and be rejected by the Michelson runtime,
> > surfacing as a misleading EVM out-of-gas. (!21791)

**Delta:** my draft adds the `**Breaking change (parametric
constants):**` prefix and the `L2-1295` Linear ref. The repo entry is
already excellent on the *what / why / consequence*, but does **not**
visually flag the L1↔Tezos-X parametric divergence as a breaking
change — a reader skimming sub-section titles would only see
"Native atomic composability" and might miss the divergence note.
The convention rule "flag breaking changes explicitly" is exactly the
gap the prefix closes.

### `!21792` — stop leaking U256::MAX balance on TEZOSX_CALLER_ADDRESS

> **Already in `etherlink/CHANGES_TEZOSX.md` (Unreleased → Native
> atomic composability):**
>
> > Stop persisting a `U256::MAX` balance for the internal
> > `TEZOSX_CALLER_ADDRESS` (`0x7e205800…01`) used by `generate_alias`.
> > Earlier kernels wrote that balance to durable storage as a
> > "safety" buffer, but the surrounding `run_transaction` is
> > `CrossRuntime` so its EVM journal never commits — only the manual
> > storage write persisted, leaking a visible huge balance on
> > Blockscout. The funding has been removed (`gas_price = 0` and
> > `value = 0` in the internal call mean no pre-flight balance is
> > required), and storage version 55 cleans up the residue on
> > TezosX networks. (L2-1296)

**Delta:** the repo entry links **only the Linear issue** (`L2-1296`)
and **not the MR** (`!21792`). That violates rule 1 (link to the MR):
a releaser walking the changelog cannot jump straight to the diff.
My draft adds the `(!21792, L2-1296)` form — both refs side by side.
The storage-version bump and the irreversible-downgrade implication
also belong at the **release header** for kernel 0.3 (rule 4), not
just in this bullet.

### `!21797` — surface cross-VM call_evm logs on synthetic CRAC tx receipt

> **Already in `etherlink/CHANGES_TEZOSX.md` (Unreleased → Native
> atomic composability):**
>
> > Fix EVM logs from cross-VM `%call_evm` calls being dropped from
> > the synthetic CRAC transaction receipt. Previously
> > `commit_evm_journal_from_external` ran before
> > `extract_cross_runtime_effects`; the former calls
> > `JournalInner::finalize` which clears `inner.logs`, leaving the
> > receipt builder with an empty buffer. Only the `CracIdEvent`
> > (constructed by the receipt builder itself) survived; both the
> > precompile's `CracReceived` log and any `LOG0..LOG4` from the
> > inner EVM call were lost. The order is now reversed so the
> > receipt builder reads `inner.logs` while revm's standard
> > accumulation is still intact, restoring parity between the two
> > ways into the EVM for indexers (subgraphs, on-chain analytics,
> > ERC-1155 wallet trackers).

**Delta:** the repo entry **has no MR or Linear reference at all** —
straight rule-1 violation. My draft adds `(!21797)`. Otherwise the
wording is essentially what I would have written; this entry is the
gold standard for descriptive ("what / why / user impact") content.

### `!21807` — surface user EMIT ops from re-entrant CRAC receipts

> **Already in `etherlink/CHANGES_TEZOSX.md` (Unreleased → Native
> atomic composability):**
>
> > Surface user Michelson `EMIT` events from re-entrant inner CRACs
> > on the synthetic CRAC transaction receipt. Previously, events
> > emitted by a Michelson contract reached through a nested
> > cross-runtime call (EVM → Mich → EVM → Mich within one EVM
> > transaction) were silently discarded, breaking parity for
> > Michelson-side event indexers. (!21807)

**Delta:** my draft adds the `L2-1301` Linear ref. Otherwise
identical wording — this is the convention working as designed.

### `!21814` — nest failed re-entrant inner CRACs in DFS order

> **Not present in any `CHANGES_*.md` as of 2026-05-07.**
>
> The MR's checklist marked the changelog item as `[x]` (see the
> description) but no entry was added in this MR or any descendant.
> The "before / after" sequence-number diagram from the MR
> description is exactly the kind of user-observable change that
> belongs in the changelog: any indexer or block explorer that
> consumed the merged synthetic Michelson manager-op pre-fix saw
> failed inner CRACs ahead of their parent's transfer.

**Delta:** my draft fills the gap. This is the strongest argument
for the convention — the MR landed checked-off but the artifact is
missing.

### `!21817` — persist original_evm_source across re-entrant EVM frames

> **Not present in any `CHANGES_*.md` as of 2026-05-07.**

**Delta:** same as `!21814` — checklist marked complete, no entry
written. The user-visible symptom (alias cache poisoning across
nested CRACs) deserves a bullet so operators can correlate the fix
with any spurious entries on their existing alias-cache state.

### `!21820` — Native recording for Implicit and Ethereum accounts

> **Not present in any `CHANGES_*.md` as of 2026-05-07.**

**Delta:** the MR is part of the transitive-address-translation
suite (RFC). Without a changelog entry, downstream consumers of the
classification storage have no signal that the native variant of
`Origin` is now written on commit / reveal. My draft surfaces it.

### `!21824` — Native recording for KT1

> **Not present in any `CHANGES_*.md` as of 2026-05-07.**

**Delta:** same gap as `!21820`. Together they should land as two
adjacent bullets in `Native atomic composability`, both pointing at
the same RFC.

### `!21806` — derive Michelson per-op cap from the EVM per-tx cap

> **Not present in any `CHANGES_*.md` as of 2026-05-07.**

**Delta:** pure refactor, follow-up to `!21791`. The MR's checkbox
left the changelog item un-ticked. My draft puts it in the
`Internals` sub-section — releasers skip that block on a normal
release scan, but reviewers diffing two kernels for a regression
need to know the constant moved crates.

### `!21785` — Include Inject_tezlink_operation in evm_supported_methods

> **Already in `etherlink/CHANGES_NODE.md` (Unreleased → RPCs
> changes):**
>
> > Include `injectTezlinkOperation` in the list of supported EVM
> > methods used by the RPC node. (!21785)

**Delta:** identical to my draft. Reference convention working as
intended.

### `!21786` — block parameter on tez_kernelVersion and tez_kernelRootHash

> **Not present in `etherlink/CHANGES_NODE.md` as of 2026-05-07.**

**Delta:** RPC surface change with a new optional parameter — a
prime "must be in the changelog" candidate. My draft lands it in the
`RPCs changes` sub-section and explicitly states the omitted-param
default to make non-breaking-ness obvious.

### `!21761` — compact_receipt_encoding feature flag

> **Not present in `etherlink/CHANGES_NODE.md` as of 2026-05-07.**

**Delta:** feature flag, opt-in, experimental. My draft lands it
under `Experimental features changes` (which already has the
"no backward-compat guarantees" boilerplate) — that's the
convention-correct landing zone for opt-in experimental surface, so
operators reading the section's preface understand the flag's
stability contract before the bullet.

### Release MRs — `!21830` (kernel 0.3) and `!21828` (EVM Node 0.58)

> **`etherlink/CHANGES_TEZOSX.md`:** still has `## Unreleased` at the
> top, with no `## Version 0.3` block. The most recent versioned
> block is `## Version 0.2 (017753c894e5bdaae7838c9501814c1ccc7290d6)`.
>
> **`etherlink/CHANGES_NODE.md`:** still has `## Unreleased` at the
> top, with no `## Version 0.58` block. The most recent versioned
> block is `## Version 0.57 (2026-04-27)`.

**Delta:** both release MRs merged on 2026-05-06 *without* moving
their respective changelog content from `Unreleased` to a versioned
block, and *without* adding a release-level cross-component
constraint header. Convention rule 4 (record the EVM-node-↔-kernel
peer version at the version header) is exactly what the absence here
illustrates. My drafted release blocks above (kernel 0.3, EVM Node
0.58) are what should have landed in the same MR as the version bump
itself.

### Summary

Of the 14 MRs surveyed (12 feature MRs + 2 release MRs):

| Status                                  | Count | MRs |
|-----------------------------------------|-------|-----|
| Entry exists, follows convention        | 3     | `!21785`, `!21791`, `!21807` |
| Entry exists, missing MR/Linear link    | 2     | `!21792` (Linear only, no MR ref), `!21797` (no ref at all) |
| **No entry at all**                     | 7     | `!21806`, `!21814`, `!21817`, `!21820`, `!21824`, `!21786`, `!21761` |
| Release MR did not move `Unreleased` → versioned block | 2 | `!21830` (kernel 0.3), `!21828` (EVM Node 0.58) |

That's 7 of 12 feature MRs **with no changelog entry**, and 2 of 2
release MRs **without a versioned release block** to anchor the new
peer-version constraint. Several of the 7 missing entries had their
changelog checkbox ticked in the MR description (e.g. `!21814`,
`!21817`) — so the gap is real and a self-checked checkbox is not
load-bearing.

The convention's value lands in two places: pushing the
**already-present** entries to add the missing MR/Linear ref (rules
1 and 2), and pushing **un-entered** changes to actually write
something — most cheaply caught by a CI lint that reads
`git log --since=last-release` and checks each MR has a matching
mention in some `CHANGES_*` file.

---

## What I deliberately *did not* write

A few cases worth calling out, because the convention is just as
much about restraint:

- **Pure-refactor MRs with no behavior change** (e.g. `!21806`)
  still get an entry — but in the `Internals` sub-section, not in
  the user-facing one. Releasers reading the changelog can skip the
  `Internals` block; reviewers comparing two kernels need it to find
  the constant-source-of-truth move.
- **Stacked MRs sharing one Linear issue** (e.g. the `L2-1300/1301/
  1302/1303/1304` chain that landed as `!21807` → `!21808` →
  `!21811` → `!21812` → `!21814` → `!21817`) get one bullet *per
  MR*, not one bullet for the whole stack. Each MR is independently
  revertible; collapsing them hides the revert surface from
  releasers triaging a regression.
- **MR descriptions that are just "Hop."** (e.g. `!21828`) are not
  an excuse to skip the changelog. The release header above is what
  I would have insisted on before approving the release MR.
