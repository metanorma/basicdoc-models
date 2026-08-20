# basicdoc-models — upgrade plan to the modern Relaton/standoc architecture

**Date:** 2026-08-20  
**Status:** Implemented on branch `chore/modern-architecture` (PR #42).  
**Reference implementation:** `relaton/relaton-models` branch `cleanup/dry-flavours` (and the matching work in `metanorma/standoc-models` vendor-wave).  
**Scope:** bring this repository to the same architectural bar — LML-first models, Rakefile build, lutaml-lml renderer, parity gates, clean submodule wiring, no legacy stack.

Post-merge remaining work lives on **consumers**: advance the `basicdoc/` submodule pin and rewrite includes `*.lutaml` → `*.lml`. Local `BibliographicItem` under `models/bibdata/` stays as a thin stub to avoid a circular basicdoc↔relaton LML include graph; full Relaton cross-includes can be revisited once consumers pin this tree.

---

## 0. Target architecture (what “done” looks like)

After the upgrade, basicdoc-models is a **single-module** repository (unlike the multi-flavour relaton-models monorepo). The root *is* the module:

```
basicdoc-models/
  models/           # LML definition modules (*.lml) — THE models
  views/            # LML diagram views (*.lml) — compose models via include
  images/           # rendered PNGs, committed
  grammars/         # RNC implementation grammars accompanying the LML
    basicdoc.rnc
    basicdoc-compile.rnc
    mathml/         # vendored/submodule MathML (keep; already present)
  Gemfile           # lutaml-lml + rake only
  Rakefile          # render / clean / verify / parity / check
  README.adoc       # [IMPORTANT] LML-is-the-model rule at top
  CLAUDE.md         # agent guidance matching relaton-models
  .github/workflows/rake.yml
```

**Non-goals for this upgrade:**
- Do **not** nest everything under a `basicdoc/` prefix — this repo *is* the basicdoc module. Consumers (relaton-models, standoc-models) already submodule it at `basicdoc/` or `grammars/basicdoc-models`.
- Do **not** invent flavour subdirectories.
- Do **not** delete historical content without an explicit decision (see §7).

**Inviolable rule (must appear in README):**

> The models ARE the LML files (`models/*.lml`, `views/*.lml`). RNC in `grammars/` are implementation grammars that accompany the LML — never a substitute. This cannot be violated.

---

## 0.1 Views vs models (hard separation — cannot be violated)

This is the same rule applied in relaton-models. Mis-separation is the most
common failure mode when migrating legacy LutaML trees.

| Path | Role | May contain | Must NOT contain |
|------|------|-------------|------------------|
| `models/**/*.lml` | **Definition modules** | `class`, `enum`, `data_type`, their attributes and nested `definition { }` blocks | `diagram` / `view` keywords, `association { }` blocks, `title`/`caption`, includes of other diagrams |
| `views/*.lml` | **Rendered diagrams** | exactly one `diagram` (or `view`) block; `include` of definition modules (relative paths); `association` blocks; `title` / `caption` | New class/enum/data_type bodies (those belong in `models/`); duplicated class stubs that only exist so a diagram can name them |

**Consequences for this upgrade:**

1. **Extract before render.** If a file under `models/` currently starts with
   `diagram …` or embeds `association { }`, split it: definitions →
   `models/<domain>/*.lml`, diagram shell → `views/<Name>.lml` that
   `include`s those definitions. (This is exactly what ogc required in
   relaton-models — the "model" was a full diagram file.)
2. **Views compose; models define.** A view's only job is to select modules
   and declare the associations/title worth drawing. Adding a new attribute
   never means editing a view — only the owning model file.
3. **One diagram per view file.** No multi-diagram view files.
4. **Includes are relative and cross-module when needed**
   (`../models/…`, `../grammars/relaton-models/relaton/models/…`). Never
   copy a base/Relaton/Basicdoc type into a local models folder as a stub.
5. **Rakefile only globs `views/*.lml` for PNG output.** Anything under
   `models/` is never a render input. The parity gate must fail if a
   `diagram` keyword appears under `models/`.
6. **PNGs are named after the view stem**, not after an arbitrary model
   class. `views/Blocks.lml` → `images/Blocks.png`.

`rake parity` checklist items to enforce this:

- [ ] `rg -n '^(diagram|view)\b' models` → empty
- [ ] `rg -n '^(class|enum|data_type)\b' views` → empty (associations and
      includes only inside the diagram block)
- [ ] Every `views/*.lml` contains exactly one `diagram`/`view` keyword
- [ ] Every `include` target from a view resolves to a file under `models/`
      (or a submodule models path), never under `views/`


## 1. Audit findings (current state vs target)

| Area | Current | Target | Severity |
|------|---------|--------|----------|
| Model extension | 137× `.lutaml` (121 models + 16 views); **0** `.lml` | All `.lml` | High |
| Build tool | Cimas `Makefile` calling `lutaml lml generate` | `Rakefile` + `lutaml-lml generate` | High |
| Gem stack | `lutaml` + `lutaml-uml` (legacy) | `lutaml-lml` ≥ 0.1.3 + `rake` | High |
| Gemfile.lock | absent | committed after `bundle lock` | Medium |
| PNG verify | `file(1)` magic check; **skipped on Windows** | Pure-Ruby `\x89PNG` check (all OSes) | Medium |
| CI | `.github/workflows/make.yml` → shared `metanorma/ci` `model-make.yml@main` | Self-contained `rake.yml` (relaton-models pattern): graphviz setup, Ruby 3.3, `rake clean render verify parity`, `submodules: recursive` | High |
| README | No LML-is-the-model rule; badge points at `workflow:make`; still says Relaton lives at metanorma/relaton-models without path guidance | [IMPORTANT] block; badge → `rake`; building section with submodule + rake commands | High |
| CLAUDE.md | missing | present | Medium |
| Submodule `grammars/relaton-models` | **uninitialized** (`-4807cc7…`); URL `metanorma/relaton-models`; expects old top-level `grammars/biblio.rnc` | Initialized; pin to a SHA that has `relaton/grammars/biblio.rnc` (post-hierarchy PR); update all consumers of that path | High |
| `grammars/make.sh` | Clones jing-trang, `cp relaton-models/grammars/biblio.rnc .`, trang RNC→RNG | Either: (a) path-updated script under rake task, or (b) drop RNG generation from this repo if standoc-models is the grammar hub | Medium |
| Root `make.sh` | Dead `lutaml-uml` one-liner | Delete | Low |
| Legacy comment syntax | `*\| … \|*` multiline “history” blocks in views and some models (e.g. `models/BasicDocument.lutaml`, `views/Blocks.lutaml`) | Convert history into `definition { }` prose or drop (git history is the history); must parse under lutaml-lml | High |
| Brace spacing | **47** files with `class Foo{` (no space) | Normalize to `class Foo {` (style; lutaml-lml accepts both via `spaces?`) | Low |
| View quality | Mix of thin wrappers (`BasicDocument` view = single include, no associations) and rich association diagrams (`IdElements`, `TextElements`) | Every view that represents a diagram must include its models **and** declare associations; thin wrappers that just re-include one file should either gain associations or be justified | Medium |
| Model/view split | Mostly correct, but **unverified** — some models carry history/`*|` junk; thin views; no automated gate | Hard split per §0.1; parity fails on `diagram` under `models/` or class bodies under `views/` | **High** |
| RNC ↔ LML parity | No gate; RNC exists (`basicdoc.rnc`, `basicdoc-compile.rnc`) | `rake parity` asserts RNC present, every view has a model include graph, every view has a PNG | Medium |
| WSD leftovers | none | keep none | OK |
| Cross-repo DRY | relaton-models now submodules **this** repo for Image/BasicElement/BasicBlock | After upgrade, relaton-models pin advances; standoc-models may also submodule basicdoc — keep the contract: **this repo is the sole source of Basicdoc LML** | High (contract) |

### 1.1 Parser / content landmines (must fix before lutaml-lml render)

Discovered patterns that will break or degrade under `lutaml-lml` (see lutaml/lutaml-lml#6 for title/definition fixes; use ≥ 0.1.3):

1. **`*\| … \|*` history blocks** — not valid LML. They appear as the first body content of several views and of `models/BasicDocument.lutaml`. Strip or convert before any render attempt.
2. **Nested braces inside `definition { }`** — fixed in lutaml-lml 0.1.3 (balanced braces). Still audit for unescaped `}` that are meant as prose.
3. **Titles with parentheses** — fixed in 0.1.3 for quoted titles. Prefer double-quoted titles everywhere.
4. **Includes still say `.lutaml`** — rewrite to `.lml` in the same commit as the rename.

### 1.2 Submodule path break (critical consumer impact)

`grammars/make.sh` today:

```sh
cp relaton-models/grammars/biblio.rnc .
```

After relaton-models hierarchy unification the file lives at:

```
relaton-models/relaton/grammars/biblio.rnc
relaton-models/relaton/grammars/biblio-standoc.rnc
relaton-models/relaton/grammars/biblio-compile.rnc
```

Any script, CI step, or human doc that assumes top-level `grammars/biblio.rnc` inside the submodule **is already wrong** once the relaton-models PR merges. This upgrade must land in lockstep with that PR (or immediately after).

---

## 2. Workstreams

### WS-A — Toolchain swap (Makefile → Rakefile, gems → lutaml-lml)

**Deliverables**
- Replace `Gemfile` with:
  ```ruby
  source "https://rubygems.org"
  gem "lutaml-lml", ">= 0.1.3"
  gem "rake"
  ```
- Add root `Rakefile` modelled on relaton-models (single-module variant):

  ```ruby
  PNG_MAGIC = "\x89PNG\r\n\x1a\n".b
  VIEWS  = Rake::FileList["views/*.lml"]
  IMAGES = VIEWS.pathmap("images/%n.png")

  task default: :render
  task render: IMAGES

  rule(%r{^images/.+\.png$}) do |t|
    source = t.name.sub(/^images\//, "views/").sub(/\.png$/, ".lml")
    mkdir_p "images"
    sh "lutaml-lml", "generate", source, "-o", t.name, "-t", "png"
  end

  task :clean  { rm_f IMAGES.existing }
  task :verify do
    pngs = Rake::FileList["images/*.png"].existing.sort
    bad = pngs.reject { |p| File.binread(p, 8) == PNG_MAGIC }
    abort "verify: #{bad.size} of #{pngs.size} invalid" unless bad.empty?
    puts "verify: #{pngs.size} PNG file(s) OK"
  end

  task :parity do
    errors = []
    errors << "missing grammars/basicdoc.rnc" unless File.exist?("grammars/basicdoc.rnc")
    errors << "missing models/" unless Dir.exist?("models")
    VIEWS.each do |v|
      png = "images/#{File.basename(v, ".lml")}.png"
      # presence of a view implies a committed (or regenerable) diagram name
      errors << "no view models included? #{v}" if File.read(v).none? { |l| l =~ /include / }
    end
    # every domain dir under models/ should be reachable from at least one view
    # (implement as: collect include targets from views, diff against models/**/*.lml)
    abort "parity: …" unless errors.empty?
    puts "parity: OK"
  end

  task check: %i[render verify parity]
  ```

- Delete root `Makefile`, root `make.sh`.
- Decide fate of `grammars/make.sh` (see WS-D).
- `bundle lock`; commit `Gemfile.lock`.
- Local gate: `bundle exec rake check` produces 16 valid PNGs byte-comparable to current (or intentionally improved).

**Acceptance**
- [ ] No Makefile remains
- [ ] `bundle exec rake check` exits 0 on macOS and Linux
- [ ] CI job green on ubuntu/macos/windows

---

### WS-B — `.lutaml` → `.lml` rename, include rewrite, **enforce views/models split**

**Deliverables**
- `git mv` every `models/**/*.lutaml` and `views/*.lutaml` → `.lml` (137 files).
- Rewrite every `include …/*.lutaml` → `.lml` inside those files.
- Normalize `class Foo{` → `class Foo {` across models (47 files) for consistency with relaton-models style.
- Strip or convert every `*\| … \|*` block:
  - **Preferred:** delete the change-log prose (it belongs in git history). Keep a one-line `definition { }` on the class/diagram if missing.
  - **Alternative:** move a short summary into `definition { }` (no nested raw history markers).
- Add `title "…"` to every view that lacks one.
- **Apply §0.1 separation (mandatory in this workstream, not deferred):**
  - Audit `models/` for `diagram`/`view`/`association` — extract any offenders into `views/`.
  - Audit `views/` for `class`/`enum`/`data_type` bodies — extract into `models/<domain>/` and replace with `include`.
  - Ensure every view file has exactly one `diagram` block and only `include` + `association` + title/caption inside it.
  - Rakefile / parity must fail the build if the separation is violated (see §0.1 checklist).

**Acceptance**
- [ ] `find . -name '*.lutaml' -not -path './.git/*' | wc -l` → 0 (except possibly inside uninitialized submodule worktrees — those get their own upgrade)
- [ ] `rg '\.lutaml' models views` → 0
- [ ] `rg '^\*\|' models views` → 0
- [ ] `rake render` succeeds for all 16 views

**Risk:** views that currently “work” under the old `lutaml` CLI only because it was more permissive. Mitigate by rendering **one view at a time** and fixing parse errors as they appear (same method used on relaton-models: bisect includes).

---

### WS-C — CI modernization

**Deliverables**
- Add `.github/workflows/rake.yml` (copy structure from relaton-models):
  - `actions/checkout@v4` with `submodules: recursive`
  - Install graphviz on linux/mac/windows if `dot` missing
  - `ruby/setup-ruby@v1` with Ruby 3.3 + bundler-cache
  - `bundle exec rake clean render`
  - `bundle exec rake verify`
  - `bundle exec rake parity`
- Remove or retire `.github/workflows/make.yml` (stop depending on `metanorma/ci` `model-make.yml` — that path is what bit relaton-models when plantuml-setup was deleted upstream).
- Update README badge: `workflow:make` → `workflow:rake`.

**Acceptance**
- [ ] PR CI green on the three OS matrix entries
- [ ] No reference to `model-make.yml` or `lutaml-uml` remains in `.github/`

---

### WS-D — Submodules & grammar pipeline

**D1. `grammars/relaton-models` submodule**

| Step | Action |
|------|--------|
| 1 | `git submodule update --init grammars/relaton-models` |
| 2 | Point at a SHA **after** the relaton-models hierarchy PR merges (path `relaton/grammars/biblio*.rnc`) |
| 3 | Update URL if the canonical remote is `relaton/relaton-models` rather than `metanorma/relaton-models` (confirm with the org; today `.gitmodules` says metanorma) |
| 4 | Fix every in-repo reference from `relaton-models/grammars/biblio.rnc` → `relaton-models/relaton/grammars/biblio.rnc` |

**D2. `grammars/make.sh` (RNC → RNG via jing-trang)**

Options (pick one before implementing):

| Option | Pros | Cons |
|--------|------|------|
| **A. Keep, path-fix, wrap in rake** | Local RNG build still possible | jing-trang bootstrap is heavy; duplicates standoc-models grammar hub |
| **B. Delete; document that standoc-models is the RNG hub** | Matches “grammar hub” reality; less CI surface | Anyone relying on RNG artifacts from this repo must switch |
| **C. Keep RNG committed, generate in a rare manual task** | No CI jing dependency | RNG can drift from RNC |

**Recommendation:** **B** if standoc-models already vendors/compiles basicdoc RNG (verify during implementation). Otherwise **A** with a `rake grammar` task and cached jing-trang.

**D3. MathML**

- `grammars/mathml` already holds vendored MathML 4 (see commit d2a94b1). Leave as-is unless a submodule is cleaner; out of scope unless parity requires it.

**Acceptance**
- [ ] `git submodule status` shows initialized, non-dash SHAs
- [ ] No script references `relaton-models/grammars/biblio.rnc` at the old path
- [ ] Decision on D2 recorded in README and CLAUDE.md

---

### WS-E — Documentation

**Deliverables**
- `README.adoc`
  - `[IMPORTANT]` block (LML = model, RNC = implementation) immediately after the opening blurb
  - Building section: submodule init, `bundle install`, `rake render/verify/parity/check/clean`
  - Correct Relaton pointer: models live in `relaton/relaton-models` (or whatever the canonical remote is), base grammars at `relaton/grammars/`
  - Badge → rake workflow
- `CLAUDE.md` (agent guide), covering:
  - Inviolable LML rule
  - Layout (single-module)
  - Build commands
  - Submodule contract with relaton-models / standoc-models
  - Parser gotchas
  - “Do not vendor Basicdoc types elsewhere”
- Delete obsolete references to `lutaml-uml`, `make.sh`, PlantUML/WSD.

**Acceptance**
- [ ] New contributor can clone, `git submodule update --init --recursive`, `bundle install`, `rake check` using only the README
- [ ] CLAUDE.md exists and matches reality

---

### WS-F — Model quality pass (after green render)

Not blocking the toolchain cutover, but required before calling the upgrade “complete”:

1. **Thin views (after §0.1 split is clean):** `views/BasicDocument.lml` currently only includes `models/BasicDocument.lml` and declares no associations. Expand it (and any peer thin views) so the rendered diagram shows the real graph (identifier, bibdata, sections, references, …), with associations matching attribute relationships. Still no class bodies in the view — only includes + associations.
2. **Cross-includes to Relaton types:** where Basicdoc attributes reference Relaton concepts (e.g. bibliographic types inside `bibdata/`), include them via the relaton-models submodule using **relative paths** — never stub `class X <<Relaton>> {}` copies. Pattern from relaton-models:
   ```
   include ../grammars/relaton-models/relaton/models/BibliographicItem.lml
   ```
   (exact relative path depends on final submodule layout).
3. **Domain MECE:** confirm each file under `models/<domain>/` defines types of that domain only; no diagram keyword under `models/`.
4. **RNC alignment notes:** spot-check that `grammars/basicdoc.rnc` elements still correspond 1:1 to LML classes (document, section, BasicBlock, …). Open issues for drift; full LML→RNC generation is **out of scope** (same as relaton-models).

---

## 3. Suggested execution order

```
1. Branch chore/modern-architecture off main
2. WS-A skeleton (Gemfile + Rakefile) without deleting Makefile yet
3. WS-B rename + strip *| blocks + brace normalize  (one commit)
4. bundle exec rake render — fix parse errors until 16/16 PNGs
5. Delete Makefile, make.sh; commit toolchain swap
6. WS-C CI
7. WS-D submodules + grammar path fixes
8. WS-E docs (README IMPORTANT + CLAUDE.md)
9. rake check green locally + CI
10. WS-F quality pass (can be a follow-up PR if needed)
11. Open PR; coordinate merge with relaton-models hierarchy PR
```

**Coordination dependency:**  
relaton-models already submodules this repo at `basicdoc/`. Sequence:

1. Land **this** upgrade PR on basicdoc-models `main`.
2. Advance the submodule pin on relaton-models (and standoc-models if applicable).
3. Land relaton-models hierarchy PR if not already merged (it consumes `basicdoc/models/.../*.lutaml` today — after WS-B those paths become `*.lml`; update includes in the same pin-advance commit).

---

## 4. Verification matrix

| Check | Command / method |
|-------|------------------|
| Render all diagrams | `bundle exec rake render` |
| PNG integrity | `bundle exec rake verify` → `16 PNG file(s) OK` |
| LML/RNC presence | `bundle exec rake parity` |
| Full gate | `bundle exec rake check` |
| No legacy extensions | `find models views -name '*.lutaml' \| wc -l` → 0 |
| No legacy comments | `rg '\*\|' models views` → 0 |
| No legacy gems | `rg 'lutaml-uml|lutaml lml' -g'!UPGRADE-PLAN.md'` → 0 |
| Submodule initialized | `git submodule status` no leading `-` |
| CI | GitHub Actions `rake` workflow green ×3 OS |
| Consumer smoke | In relaton-models: bump basicdoc pin, `rake relaton bsi` still renders |

---

## 5. Explicit non-actions (do not “clean up” without asking)

Per global safety rules and the relaton-models lessons:

- **Do not delete** MathML vendor trees, RNC grammars, or committed PNGs because they look redundant.
- **Do not delete** the relaton-models submodule because “parity doesn’t need it” — consumers and grammar scripts may.
- **Do not** hand-roll `to_h` / serialization anywhere (N/A today; keep it that way).
- **Do not** force-push main or tag releases from this work.
- **Do not** use `git add -A`; stage by explicit path.

---

## 6. Effort estimate

| Workstream | Estimate | Notes |
|------------|----------|-------|
| WS-A Toolchain | S | Pattern already proven in relaton-models |
| WS-B Rename + syntax | M | 137 renames easy; `*\|` stripping + first lutaml-lml parse pass is the real work |
| WS-C CI | S | Copy/adapt rake.yml |
| WS-D Submodules | S–M | Depends on relaton-models merge timing + D2 decision |
| WS-E Docs | S | |
| WS-F Quality | M | Can split to PR2 |
| **Total to green `rake check` + CI** | **~1 focused session** after relaton-models PR is available to pin | |
| **Total including WS-F** | **+1 session** | |

---

## 7. Open decisions (resolved)

1. **Canonical relaton-models remote:** `relaton/relaton-models` (submodule URL updated; pin `0a5add9` on `cleanup/dry-flavours` tip).
2. **Grammar RNG generation (D2):** **B** — deleted `grammars/make.sh`; standoc-models is the RNG hub.
3. **History blocks:** deleted entirely; short `definition { }` retained where already present.
4. **WS-F:** landed in the same PR — expanded `BasicDocument`, `Sections`, and `Blocks` views.

---

## 8. Reference commits / PRs

- relaton-models `cleanup/dry-flavours`: hierarchy under `relaton/`, Rakefile, `.lml`, parity, basicdoc submodule consumer
- lutaml/lutaml-lml#6 — titles with parentheses/Unicode; nested braces in definitions (need ≥ 0.1.3)
- standoc-models vendor-wave — history grafts + restore pattern (not required here; basicdoc has no flavour split)

---

## 9. First concrete commands (when execution starts)

```sh
cd ~/src/mn/basicdoc-models
git checkout -b chore/modern-architecture
# WS-A+B will land here; do not start until this plan is accepted
```

When accepted, execute WS-A → WS-E in order, keep WS-F optional/follow-up, and open the PR with a body that links this plan.
