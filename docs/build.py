#!/usr/bin/env python3
"""Regenerate docs/*.html from the canonical Markdown at the repo root.

The Markdown files are the source of truth; the HTML is what GitHub Pages serves.
Run this after editing PRIVACY.md or TERMS.md, and commit both:

    python3 docs/build.py

Deliberately dependency-free — it handles only the subset of Markdown these
documents use (headings, paragraphs, lists, tables, bold, inline code, links,
blockquotes).
"""
import html
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOCS = os.path.join(ROOT, "docs")

PAGES = [("PRIVACY.md", "privacy.html", "Privacy Policy"),
         ("TERMS.md", "terms.html", "Terms of Service")]

TEMPLATE = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title} — AI Usage Limits</title>
<link rel="stylesheet" href="style.css">
</head>
<body>
<div class="wrap">
{body}
<footer>
  <a href="index.html">AI Usage Limits</a> &middot;
  <a href="https://github.com/stavrop/ai-usage-limits">GitHub</a> &middot;
  Apache-2.0 &copy; 2026 Georgios Stavropoulos
</footer>
</div>
</body>
</html>
"""


def inline(text):
    text = html.escape(text)
    text = re.sub(r"`([^`]+)`", r"<code>\1</code>", text)
    text = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", text)
    text = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r'<a href="\2">\1</a>', text)
    text = re.sub(r"&lt;(https?://[^&]+)&gt;", r'<a href="\1">\1</a>', text)
    return text


def convert(md):
    lines = md.split("\n")
    out, i = [], 0
    while i < len(lines):
        line = lines[i]
        if not line.strip():
            i += 1
            continue
        if line.startswith("|"):
            rows = []
            while i < len(lines) and lines[i].startswith("|"):
                rows.append(lines[i])
                i += 1
            cells = [[c.strip() for c in r.strip("|").split("|")] for r in rows]
            body = [r for r in cells if not all(set(c) <= set("-: ") for c in r)]
            out.append("<table>")
            if body:
                out.append("<tr>" + "".join(f"<th>{inline(c)}</th>" for c in body[0]) + "</tr>")
                for row in body[1:]:
                    out.append("<tr>" + "".join(f"<td>{inline(c)}</td>" for c in row) + "</tr>")
            out.append("</table>")
            continue
        heading = re.match(r"^(#{1,4})\s+(.*)", line)
        if heading:
            level = len(heading.group(1))
            out.append(f"<h{level}>{inline(heading.group(2))}</h{level}>")
            i += 1
            continue
        if line.startswith("> "):
            out.append(f"<blockquote>{inline(line[2:])}</blockquote>")
            i += 1
            continue
        if re.match(r"^\s*[-*]\s+", line):
            out.append("<ul>")
            while i < len(lines) and re.match(r"^\s*[-*]\s+", lines[i]):
                item = re.sub(r"^\s*[-*]\s+", "", lines[i])
                out.append(f"<li>{inline(item)}</li>")
                i += 1
            out.append("</ul>")
            continue
        para = []
        while (i < len(lines) and lines[i].strip()
               and not lines[i].startswith(("#", "|", "> "))
               and not re.match(r"^\s*[-*]\s+", lines[i])):
            para.append(lines[i].strip())
            i += 1
        out.append(f"<p>{inline(' '.join(para))}</p>")
    return "\n".join(out)


def main():
    for src, dest, title in PAGES:
        md = open(os.path.join(ROOT, src)).read()
        with open(os.path.join(DOCS, dest), "w") as f:
            f.write(TEMPLATE.format(title=title, body=convert(md)))
        print("wrote docs/" + dest)


if __name__ == "__main__":
    main()
