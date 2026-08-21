"""Validate examples/*.xml against grammars/basicdoc-compile.rnc.

rnc2rng limitations handled by preprocessing: includes are inlined
manually (it resolves them against the CWD), and `external` vendored
grammars are stubbed (not exercised by fixtures).
"""
import os
import re
import sys
from pathlib import Path

import rnc2rng
from lxml import etree

ROOT = Path(__file__).resolve().parent.parent
G = ROOT / "grammars"


def expand(src_text: str, base: Path, seen: set) -> str:
    def repl(m):
        rel = m.group(1).strip('"')
        target = (base / rel).resolve()
        if target in seen or not target.exists():
            return ""
        seen.add(target)
        return expand(target.read_text(), target.parent, seen)

    text = re.sub(r'^\s*include\s+("[^"]+"|\'[^\']+\')\s*(\{[^}]*\})?\s*$', repl, src_text, flags=re.M)
    text = re.sub(r"^(\w+) = external .*$", r"\1 = element external-\1 { text }", text, flags=re.M)
    # rnc2rng has no `grammar { }` wrapper support: unwrap
    if re.search(r"^\s*grammar \{\s*$", text, flags=re.M):
        text = re.sub(r"^\s*grammar \{\s*$", "", text, flags=re.M)
        lines = text.rstrip().splitlines()
        while lines and lines[-1].strip() == "":
            lines.pop()
        if lines and lines[-1].strip() == "}":
            lines.pop()
        text = "\n".join(lines) + "\n"
    return text


os.chdir(G)
combined = expand(Path("basicdoc-compile.rnc").read_text(), G, {G / "basicdoc-compile.rnc"})
rng = rnc2rng.loads(combined)
schema = etree.RelaxNG(etree.fromstring(rnc2rng.dumps(rng).encode()))

failed = 0
for xml_path in sorted((ROOT / "examples").glob("*.xml")):
    doc = etree.parse(str(xml_path))
    if schema.validate(doc):
        print(f"fixtures:xml OK {xml_path.name}")
    else:
        failed += 1
        print(f"fixtures:xml FAIL {xml_path.name}")
        for e in schema.error_log:
            print(f"  line {e.line}: {e.message}")
sys.exit(1 if failed else 0)
