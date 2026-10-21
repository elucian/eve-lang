"""The manual build: decide every page and every copied folder, then write them or compare them with the disk."""
import filecmp
import re
import shutil
from pathlib import Path

import manual
import model
from model import ROOT, read_text, write_text

TEMPLATE_PAGES = [("features.md", "features.md", lambda s: manual.features_blocks(s["levels"])),
                  ("tests.md", "tests.md", lambda s: manual.tests_blocks(s["suites"])),
                  ("performance.md", "performance.md", lambda s: manual.performance_blocks(s["runs"], s["descriptions"]))]


def sources(root):
    levels = model.load_levels(root)
    return {"levels": levels, "suites": model.load_suites(root), "runs": model.bench_runs(root),
            "descriptions": model.bench_descriptions(root)}


def template_page(root, name, template, blocks):
    existing = root / "manual" / name
    if existing.is_file():
        text = model.read_text(existing)
    else:
        text = read_text(manual.TEMPLATES / template)
        text = re.sub(r"\A(?:<!--.*?-->\n)+", "", text, flags=re.S)
    for block, body in blocks.items():
        text = manual.put(text, block, body)
    return text


def pages(root):
    """-> {relative path in the manual: text}."""
    src = sources(root)
    out = {}
    for name, template, blocks in TEMPLATE_PAGES:
        out[name] = template_page(root, name, template, blocks(src))
    examples = manual.examples_by_feature(root, src["suites"])
    for lv in src["levels"]:
        out["levels/%s.md" % lv["id"]] = manual.level_page(lv, examples)
    lex = root / "spec" / "lexical"
    for name, fn in (("keywords", manual.keywords_page), ("operators", manual.operators_page),
                     ("delimiters", manual.delimiters_page)):
        if (lex / (name + ".json")).is_file():
            out["reference/%s.md" % name] = fn(model.jload(lex / (name + ".json")))
    return out


def copies(root):
    """-> [(source folder, relative target in the manual)]: the user documents of each component and driver."""
    found = []
    for base, prefix in ((root / "design" / "components", ""), (root / "drivers", "drivers/")):
        if base.is_dir():
            for d in sorted(base.iterdir()):
                if (d / "doc").is_dir():
                    found.append((d / "doc", prefix + d.name))
    return found


def same_tree(a, b):
    if not b.is_dir():
        return False
    cmp = filecmp.dircmp(a, b)
    if cmp.left_only or cmp.right_only or cmp.diff_files or cmp.funny_files:
        return False
    return all(same_tree(a / d, b / d) for d in cmp.common_dirs)


def run(root=ROOT, out=None, check=False):
    """Write the manual to `out` (default manual/ of the repository). With check=True write nothing and return
    the list of stale pages."""
    out = Path(out) if out else root / "manual"
    stale = []
    made = pages(root)
    for rel, text in made.items():
        dst = out / rel
        if not dst.is_file() or model.read_text(dst) != text:
            stale.append(rel)
            if not check:
                write_text(dst, text)
    # a generated folder holds only what the generator makes: a page that left the sources is removed
    for sub in ("levels", "reference"):
        folder = out / sub
        if folder.is_dir():
            keep = {Path(r).name for r in made if r.startswith(sub + "/")}
            for f in folder.glob("*.md"):
                if f.name not in keep:
                    stale.append("%s/%s (removed)" % (sub, f.name))
                    if not check:
                        f.unlink()
    for srcdir, rel in copies(root):
        dst = out / rel
        if not same_tree(srcdir, dst):
            stale.append(rel + "/")
            if not check:
                shutil.rmtree(dst, ignore_errors=True)
                shutil.copytree(srcdir, dst)
    return stale
