#!/usr/bin/env python3
"""Publish docs/GUIDE.md to the GitHub wiki as one page per chapter.

docs/GUIDE.md stays the single source of truth; this script splits it at
its `##` headings, rewrites the guide's internal `#anchor` links into wiki
page links, and generates Home.md and _Sidebar.md.

Usage:  scripts/sync-wiki.py <path-to-cloned-wiki>
"""
import os
import re
import sys

GUIDE = os.path.join(os.path.dirname(__file__), "..", "docs", "GUIDE.md")


def anchor(heading):
    """Reproduce GitHub's anchor slug for a heading."""
    a = re.sub(r"[^\w\s-]", "", heading.lower())
    return re.sub(r"\s+", "-", a.strip())


def pagename(heading):
    """Wiki page name: no punctuation, spaces become hyphens."""
    p = re.sub(r"[^\w\s-]", "", heading)
    return re.sub(r"\s+", "-", p.strip())


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: sync-wiki.py <path-to-cloned-wiki>")
    wiki = sys.argv[1]
    if not os.path.isdir(os.path.join(wiki, ".git")):
        sys.exit(f"{wiki} is not a git clone of the wiki")

    src = open(GUIDE).read()

    # Split into (heading, body) chapters at every `##`.
    parts = re.split(r"^## (.+)$", src, flags=re.M)
    preamble = parts[0]
    chapters = [(parts[i], parts[i + 1]) for i in range(1, len(parts), 2)]
    chapters = [(h, b) for h, b in chapters if h != "Table of Contents"]

    # Present them in the guide's own Table of Contents order, which is
    # the logical reading order — the physical order of the file is just
    # the order chapters happened to be written in. Anything the TOC does
    # not list (the closing worked example) keeps its file position, at
    # the end.
    toc_order = re.findall(r"^\d+\. \[(.+?)\]\(#", src, flags=re.M)
    rank = {h: i for i, h in enumerate(toc_order)}
    chapters.sort(key=lambda hb: rank.get(hb[0], len(rank)))

    # anchor -> page name, so cross-references become wiki links.
    links = {anchor(h): pagename(h) for h, _ in chapters}

    def rewrite(text):
        def sub(m):
            return "](%s)" % links.get(m.group(1), "#" + m.group(1))
        text = re.sub(r"\]\(#([a-z0-9\-]+)\)", sub, text)
        # Chapters are their own pages now; the trailing rule is noise.
        return text.strip().rstrip("-").rstrip() + "\n"

    # Clear out previously generated pages before writing.
    for f in os.listdir(wiki):
        if f.endswith(".md"):
            os.remove(os.path.join(wiki, f))

    for heading, body in chapters:
        page = pagename(heading)
        with open(os.path.join(wiki, page + ".md"), "w") as fh:
            fh.write("# %s\n\n%s" % (heading, rewrite(body)))

    intro = preamble.split("---")[0].replace("# OpenRPG User's Guide", "").strip()
    intro = re.sub(r"\]\(#([a-z0-9\-]+)\)",
                   lambda m: "](%s)" % links.get(m.group(1), "#" + m.group(1)), intro)

    toc = "\n".join("%d. [%s](%s)" % (i, h, pagename(h))
                    for i, (h, _) in enumerate(chapters, 1))

    with open(os.path.join(wiki, "Home.md"), "w") as fh:
        fh.write(
            "# OpenRPG User's Guide\n\n%s\n\n"
            "> Generated from `docs/GUIDE.md` in the main repository by "
            "`scripts/sync-wiki.py` — edit the guide there, not these pages.\n\n"
            "## Contents\n\n%s\n" % (intro, toc))

    with open(os.path.join(wiki, "_Sidebar.md"), "w") as fh:
        fh.write("### [OpenRPG User's Guide](Home)\n\n%s\n" % "\n".join(
            "- [%s](%s)" % (h, pagename(h)) for h, _ in chapters))

    print("wrote %d chapter pages + Home.md + _Sidebar.md to %s"
          % (len(chapters), wiki))


if __name__ == "__main__":
    main()
