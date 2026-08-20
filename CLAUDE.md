# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Architectural rule (cannot be violated)

**The models ARE the LML files.** Every model is defined in LutaML: `models/**/*.lml` are the definition modules, `views/*.lml` are the diagram views. The RNC files in `grammars/` are implementation grammars that *accompany* the LML models — never a substitute for them. This cannot be violated. Enforced by `rake parity`.

This repository is the **sole source** of Basicdoc LML. Consumers (relaton-models, standoc-models) submodule it — never vendor Basicdoc types (`Image`, `BasicElement`, `BasicBlock`, …) into those repos.

## Views vs models (hard separation)

| Path | Contains | Must NOT contain |
|------|----------|------------------|
| `models/**/*.lml` | `class` / `enum` / `data_type` definitions only | `diagram`, `view`, `association`, `title` |
| `views/*.lml` | one `diagram`/`view`, `include`s, `association`s, title/caption | class/enum/data_type bodies |

Rakefile globs **only** `views/*.lml` for PNG output. `rake parity` fails if a `diagram` keyword appears under `models/` or a class body appears under `views/`. Cross-repo reuse = relative `include` of the real file — never a stub copy under the consumer's `models/`.

## Repository layout

Single-module repository: the root *is* the Basicdoc module (unlike multi-flavour monorepos). Do not nest under a `basicdoc/` prefix inside this repo; consumers already mount the submodule at `basicdoc/` or `grammars/basicdoc-models`.

| Path | Role |
|------|------|
| `models/` | LML class definitions, grouped by domain (`blocks/`, `textelements/`, `idelements/`, `sections/`, `change/`, …) plus root `BasicDocument.lml` |
| `views/` | LML diagram views (one file per diagram). Include models and declare associations |
| `images/` | Rendered PNGs from views — committed |
| `grammars/basicdoc.rnc`, `grammars/basicdoc-compile.rnc` | Implementation RNC accompanying the LML |
| `grammars/mathml/` | Vendored MathML 4 (leave as-is) |
| `grammars/relaton-models` | Submodule of [relaton/relaton-models](https://github.com/relaton/relaton-models) (bibliographic base; pin post-hierarchy layout under `relaton/`) |

Domain MECE: each `models/<domain>/` file defines types of that domain only. No `diagram` keyword under `models/`. Diagram-only content lives in `views/`.

## Build commands

Requires Ruby, Bundler, and Graphviz (`dot` on PATH).

```sh
git submodule update --init --recursive
bundle install
bundle exec rake render                              # regenerate images/*.png from views/*.lml (default)
bundle exec rake verify                              # pure-Ruby PNG magic-byte check (all OSes)
bundle exec rake parity                              # LML/RNC presence + view/model separation + include graph
bundle exec rake check                               # render + verify + parity
bundle exec rake clean                               # remove regenerable PNGs only
bundle exec rake images/<Name>.png                   # render a single diagram
```

Rendering uses `lutaml-lml` ≥ 0.1.3 (graphviz-backed). Until 0.1.3 is on RubyGems the Gemfile pins the fix commit via git. CI (`.github/workflows/rake.yml`) runs `rake clean render`, `rake verify`, and `rake parity` on ubuntu/windows/macos with `submodules: recursive`.

There is no separate unit-test suite; `rake check` is the gate.

## Model / view conventions

- **Definitions vs diagrams:** put classes in `models/`; put `diagram … { include …; association … }` in `views/`.
- **Includes:** paths are relative to the including file (e.g. from a view: `include ../models/idelements/Image.lml`).
- **Cross-repo types:** when a Basicdoc attribute needs a Relaton type, include via the submodule with a relative path — never stub `class X <<Relaton>> {}` copies:
  ```
  include ../grammars/relaton-models/relaton/models/BibliographicItem.lml
  ```
- **Views must show the graph:** include related models and declare associations that match attribute relationships. Do not leave thin wrappers that only re-include one model file with no associations.
- **Style:** `class Foo {` (space before brace); quoted `title` on every diagram. No legacy `*\| … \|*` history blocks — git history is the history; put a short `definition { }` on the class if needed.
- **Parser (lutaml-lml ≥ 0.1.3):** quoted titles accept parentheses/Unicode; definition bodies track brace depth. `rake render` failure usually means a broken `include` path — resolve relative to the including file.
- **Do not hand-roll serialization** on any model artifact here (LML/RNC only; no Ruby model `to_h`/`from_h`).

## Grammars and submodule

- `grammars/basicdoc.rnc` / `basicdoc-compile.rnc` stay in lockstep conceptually with LML classes (document, section, BasicBlock, …). Full LML→RNC generation is out of scope; spot-check drift and open issues.
- RNG generation is **not** this repo’s job — standoc-models is the grammar hub. Do not reintroduce jing-trang CI without an explicit decision.
- Submodule pin for `grammars/relaton-models` must point at a SHA that has `relaton/grammars/biblio*.rnc` (not the old top-level `grammars/biblio.rnc`). URL: `https://github.com/relaton/relaton-models.git`. Initialize: `git submodule update --init --recursive`.

## Consumers / coordination

| Consumer | How it uses this repo |
|----------|------------------------|
| `relaton/relaton-models` | Submodule at `basicdoc/`; views include e.g. `../../basicdoc/models/idelements/Image.lml` |
| `metanorma/standoc-models` | Grammar hub; may submodule or vendor basicdoc RNC/RNG |

After changing LML paths or extensions here, advance the submodule pin on consumers in the same coordination window. Document-structure models beyond Basicdoc remain in standoc-models — do not import those here.

## Safety (this repo)

- Do not delete MathML vendor trees, RNC grammars, committed PNGs, or the relaton-models submodule because they look unused.
- Do not force-push main or push tags from agent work. All changes via branch + PR.
- Stage by explicit path only (`git add path/to/file`) — never `git add -A` / `git add .`.
