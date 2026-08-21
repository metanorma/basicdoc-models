# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Architectural rule (cannot be violated)

**The models ARE the LML files.** Every model is defined in LutaML: `models/**/*.lml` are the definition modules, `views/*.lml` are the diagram views. The RNC files in `grammars/` are implementation grammars that *accompany* the LML models — never a substitute for them. RNC is hand-maintained in lockstep (consumed by standoc-models); LML→RNC generation is out of scope. Enforced by `rake parity` + `rake lint`.

This repository is the **sole source** of Basicdoc LML. Consumers (relaton-models, standoc-models) submodule it — never vendor Basicdoc types (`Image`, `BasicElement`, `BasicBlock`, …) into those repos.

## Views vs models (hard separation)

| Path | Contains | Must NOT contain |
|------|----------|------------------|
| `models/**/*.lml` | `class` / `enum` / `data_type` definitions only | `diagram`, `view`, `association`, `title` |
| `views/*.lml` | one `diagram`/`view`, `include`s, `association`s, title/caption | class/enum/data_type bodies |

Rakefile globs **only** `views/*.lml` for PNG output. `rake parity` fails if a `diagram` keyword appears under `models/` or a class body appears under `views/`. Cross-repo reuse = relative `include` of the real file — never a stub copy under the consumer's `models/` (the `models/bibdata/relaton/` boundary stubs are the one sanctioned exception, see below).

## Repository layout

Single-module repository: the root *is* the Basicdoc module. Do not nest under a `basicdoc/` prefix inside this repo; consumers already mount the submodule at `basicdoc/` or `grammars/basicdoc-models`.

The `models/` tree is isomorphic to the spec's ontology (CC/ISO 36010, "Lightweight document — Document metamodel"):

| Path | Tier | Contents |
|------|------|----------|
| `models/document/` | document | `BasicDocument` |
| `models/bibdata/` | document | Basicdoc-owned bibliographic basis (`BibData`, `BibDataExtensionType`, `DocumentType`) |
| `models/bibdata/relaton/` | boundary | `<<Relaton>>`/`<<Bibliography>>` stubs — see OCP policy |
| `models/contribmetadata/` | document | contribution + integrity types |
| `models/sections/` | sections | `BasicSection`, `HierarchicalSection`, `ContentSection`, `ReferencesSection` |
| `models/blocks/` | blocks | block roots (`BasicBlock`, `BasicBlockNoNotes`, `NoteBlock`) |
| `models/blocks/{paragraphs,multiparagraphs,amend,lists,tables,ancillaryblocks}/` | blocks | block families; `amend/` = in-document change markup |
| `models/inline/` | inline | `BasicElement` at the tier root |
| `models/inline/{text,id,reference,empty}/` | inline | inline element families |
| `models/change/` | changes | the collaborative patch model (`Change`, `ChangeSet`, Node/Content/Attribute changes) |
| `models/datatypes/` | cross-cutting | shared primitives (`String`, `Uri`, `Iso*Code`, `Iso8601DateTime`, …) |
| `views/` | — | one diagram per view; **view and PNG names are load-bearing** (cc-36010 embeds the PNGs) — do not rename without consumer coordination |
| `images/` | — | rendered PNGs from views — committed |
| `grammars/basicdoc.rnc`, `grammars/basicdoc-compile.rnc` | — | hand-maintained RNC; `basicdoc-compile.rnc` composes biblio+basicdoc via the submodule |
| `grammars/mathml/` | — | vendored MathML 4 (leave as-is) |
| `vendor/relaton-models` | — | submodule of [relaton/relaton-models](https://github.com/relaton/relaton-models) (reference LML + base biblio grammars) |

## bibdata is OCP

Basicdoc defines only the **basis**: `BibData`, its extension hook `ext: BibDataExtensionType`, and the single-valued `DocumentType`. Relaton and downstream models extend and implement the full bibliographic semantics. Never flesh out Relaton types here: `models/bibdata/relaton/*.lml` are boundary stubs (`class X <<Relaton>>` with a definition marking the boundary) so diagrams can reference Relaton types without importing Relaton's model graph.

## Construct doctrine (cannot be violated)

Basicdoc provides **constructs**; markup languages **specialize them as types**. Never add a per-format class where a type/specialization covers it (Note/Warning/Caution are `Admonition` + `AdmonitionType`, not classes).

- **Attribute register**: `Attribute {key, value*, scheme?}` is an open register attachable to any construct (document, section, block, inline element). Formats bind their own attribute types as register entries — basicdoc never enumerates them. Well-known keys: `id`, `class`, `lang`, `script`, `unnumbered`, `subsequence`, `format`. Do not add ad-hoc per-class slots for register material.
- **Relaxed content models**: containers (list items, multi-paragraph blocks, definition-list definitions, table cells, examples) hold `BasicBlock*`, not paragraph-only. Do not re-narrow them.
- **Composition**: a document **is** a block — `NewContentBlock` carries blocks, sections, and documents as child content; any relaxed container may hold a document.
- **Variables**: `ReferenceToVariable` resolves against the register — the model home for `{attr}`, `|substitution|`, template variables.
- **Raw/passthrough is non-markup**: inline raw = `FormattedString` (its `format` attribute admits markup into strings); block raw = string-carrying constructs + a `format` register key. No escape-hatch class.
- **Serialization profiles live in the RNC, not the model**: the `-no-id` grammar variants are profiles; the LML has no variant classes.
- **Value semantics are `data_type`s**, not flag-classes (`ImageSizeType`, `MediaType`).

## Build commands

Requires Ruby, Bundler, and Graphviz (`dot` on PATH).

```sh
git submodule update --init --recursive
bundle install
bundle exec rake render                              # regenerate images/*.png from views/*.lml (default)
bundle exec rake verify                              # pure-Ruby PNG magic-byte check
bundle exec rake lint                                # semantic lint: names, type resolution, view closure, visibility
bundle exec rake parity                              # LML/RNC presence + view/model separation + include graph
bundle exec rake check                               # render + verify + lint + parity
bundle exec rake clean                               # remove regenerable PNGs only
bundle exec rake images/<Name>.png                   # render a single diagram
bundle exec rake site                                # build the model atlas into _site/ (gitignored)
```

Rendering uses `lutaml-lml` ≥ 0.1.3 (graphviz-backed); until 0.1.3 is on RubyGems the Gemfile pins the fix commit via git. CI (`.github/workflows/rake.yml`, ubuntu-latest) runs clean/render/verify/lint/parity with `submodules: recursive`.

There is no separate unit-test suite; `rake check` is the gate.

## Model / view conventions

- **Definitions vs diagrams:** put classes in `models/`; put `diagram … { include …; association … }` in `views/`.
- **Includes:** paths are relative to the including file (e.g. from a view: `include ../models/inline/id/Image.lml`).
- **Every attribute has an explicit visibility marker** (`+`/`#`/`-`), a resolvable type, and every class/enum a `definition { }` — `rake lint` enforces all three.
- **Domain placement:** an enum lives with the family that uses it (e.g. `CellTextAlignment` in `blocks/tables/`); only cross-cutting primitives go in `datatypes/`.
- **Views must show the graph:** include related models and declare associations that match attribute relationships. No thin wrappers.
- **Style:** `class Foo {` (space before brace); quoted `title` on every diagram. No legacy `*\| … \|*` history blocks — git history is the history.
- **Parser (lutaml-lml ≥ 0.1.3):** quoted titles accept parentheses/Unicode; definition bodies track brace depth. `rake render` failure usually means a broken `include` path — resolve relative to the including file.
- **Do not hand-roll serialization** on any model artifact here (LML/RNC only; no Ruby model `to_h`/`from_h`).

## Grammars and submodule

- `grammars/basicdoc.rnc` stays in lockstep conceptually with LML classes; spot-check drift and open issues. `basicdoc-compile.rnc` includes `../vendor/relaton-models/relaton/grammars/biblio.rnc` — the submodule must be initialized for it to resolve.
- RNG generation is **not** this repo's job — standoc-models is the grammar hub. Do not reintroduce jing-trang CI without an explicit decision.
- Submodule pin for `vendor/relaton-models` must point at a SHA that has `relaton/grammars/biblio*.rnc`. Initialize: `git submodule update --init --recursive`.

## Consumers / coordination

| Consumer | How it uses this repo |
|----------|------------------------|
| `relaton/relaton-models` | Submodule at `basicdoc/`; views include e.g. `../../basicdoc/models/inline/id/Image.lml` |
| `metanorma/standoc-models` | Grammar hub; includes `basicdoc.rnc` in flavour compile grammars, ships `basicdoc.rng` into metanorma gems |
| `CalConnect/cc-lightweight-doc` | CC/ISO 36010 spec; submodules this repo at `sources/basicdoc-models` to embed `images/*.png` |

After changing LML paths here, advance the submodule pin on consumers in the same coordination window. Document-structure models beyond Basicdoc remain in standoc-models — do not import those here.

## Safety (this repo)

- Do not delete MathML vendor trees, RNC grammars, committed PNGs, or the relaton-models submodule because they look unused.
- Do not rename `views/*.lml` or `images/*.png` casually — the cc-36010 spec embeds PNGs by name.
- Do not force-push main or push tags from agent work. All changes via branch + PR.
- Stage by explicit path only (`git add path/to/file`) — never `git add -A` / `git add .`.
