# Versioning and stability policy

## Version identifiers

The model is versioned as `MAJOR.MINOR.PATCH`, applied to the model
repository as a whole (the definition modules, grammars, and diagrams
move together; they are one artifact).

- **PATCH** — editorial: definitions clarified, diagrams re-rendered,
  tooling and test changes. No construct, attribute, enumeration
  value, or cardinality changes.
- **MINOR** — additive: new constructs, new enumeration values, new
  well-known register keys, cardinality *relaxations*. Everything
  conforming to N.x conforms to N.x+1.
- **MAJOR** — removing or renaming constructs, tightening
  cardinalities, changing semantics. Requires a deprecation cycle.

Profiles and specialization modules declare the model version they
target. Because profiles may only narrow, a profile of N.x remains
valid for N.x+1 (additive releases).

## Deprecation cycle

A construct scheduled for removal in MAJOR N+1 is first marked
*deprecated* in a MINOR release of N: its definition carries a
deprecation note, and the test suite grows an instance that exercises
it (a construct without a serializable instance is unfinished —
including deprecated ones). Removal follows no sooner than the next
MAJOR release.

## Standardization snapshots

At each milestone of the associated standard (CalConnect publication,
ISO committee drafts, IS), an immutable snapshot of this repository is
tagged `standard/<milestone>` and referenced by the document. Errata
fix PATCH releases of the tagged snapshot; substantive change is
balloted through the standard, and lands here only after adoption.

## Breaking-change audit

`rake check` (lint, parity, fixtures, profiles) is the gate: any
change that would alter the accepted instance set without an
accompanying version bump is a defect, not a release.
