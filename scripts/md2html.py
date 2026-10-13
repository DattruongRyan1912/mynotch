#!/usr/bin/env python3
"""Render a MyNotch spec (a small Markdown subset) to a standalone HTML page.

Supports: headings, paragraphs, bullet/numbered lists, GFM tables,
fenced code blocks, inline code, bold, italics and links.

Usage: scripts/md2html.py input.md [output.html]
"""
import html
import re
import sys
from pathlib import Path

CSS = """
:root{--bg:#fff;--fg:#1d1d1f;--muted:#6e6e73;--line:#e5e5ea;--card:#f5f5f7;--accent:#7c5cff;--code:#f2f2f7}
@media (prefers-color-scheme:dark){:root{--bg:#141416;--fg:#f2f2f7;--muted:#a1a1a6;--line:#2c2c30;--card:#1c1c1f;--accent:#a78bfa;--code:#232327}}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--fg);font:16px/1.6 -apple-system,BlinkMacSystemFont,"SF Pro Text","Segoe UI",sans-serif}
.layout{display:grid;grid-template-columns:260px minmax(0,1fr);max-width:1200px;margin:0 auto}
nav{position:sticky;top:0;height:100vh;overflow:auto;padding:28px 16px;border-right:1px solid var(--line);font-size:14px}
nav a{display:block;color:var(--muted);text-decoration:none;padding:4px 8px;border-radius:6px}
nav a:hover{background:var(--card);color:var(--fg)}
nav a.h3{padding-left:22px;font-size:13px}
main{padding:28px 40px 80px;min-width:0}
h1{font-size:30px;margin:0 0 12px}h2{margin-top:44px;padding-top:8px;border-top:1px solid var(--line)}h3{margin-top:28px}
a{color:var(--accent)}
code{font:13px/1.5 "SF Mono",Menlo,monospace;background:var(--code);padding:1px 5px;border-radius:5px}
pre{position:relative;background:var(--code);border:1px solid var(--line);border-radius:10px;padding:14px 16px;overflow:auto}
pre code{padding:0;background:none}
.copy{position:absolute;top:8px;right:8px;font-size:12px;border:1px solid var(--line);background:var(--card);color:var(--fg);border-radius:6px;padding:3px 8px;cursor:pointer}
table{border-collapse:collapse;width:100%;margin:12px 0;font-size:14px;display:block;overflow:auto}
th,td{border:1px solid var(--line);padding:7px 10px;text-align:left;vertical-align:top}
th{background:var(--card)}
@media (max-width:860px){.layout{grid-template-columns:1fr}nav{position:static;height:auto;border-right:0;border-bottom:1px solid var(--line)}main{padding:20px}}
"""

JS = """
document.querySelectorAll('pre').forEach(pre=>{const b=document.createElement('button');b.className='copy';b.textContent='Copy';
b.onclick=()=>{navigator.clipboard.writeText(pre.querySelector('code').innerText);b.textContent='Copied';setTimeout(()=>b.textContent='Copy',1200)};pre.appendChild(b)});
"""


def slug(text: str) -> str:
    text = re.sub(r"<[^>]+>", "", text).lower()
    return re.sub(r"[^\w]+", "-", text, flags=re.UNICODE).strip("-")


def inline(text: str) -> str:
    # Protect code spans first so emphasis can wrap them without touching their contents.
    codes: list[str] = []

    def stash(match: re.Match) -> str:
        codes.append(f"<code>{html.escape(match.group(1))}</code>")
        return f"\x00{len(codes) - 1}\x00"

    text = html.escape(re.sub(r"`([^`]+)`", stash, text), quote=False)
    text = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r'<a href="\2">\1</a>', text)
    text = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", text)
    text = re.sub(r"(?<![\w*])\*([^*\s][^*]*)\*(?!\w)", r"<em>\1</em>", text)
    return re.sub(r"\x00(\d+)\x00", lambda m: codes[int(m.group(1))], text)


def split_row(line: str) -> list[str]:
    cells = re.split(r"(?<!\\)\|", line.strip().strip("|"))
    return [c.strip().replace("\\|", "|") for c in cells]


def render(md: str) -> tuple[str, str, list[tuple[int, str, str]]]:
    lines = md.splitlines()
    out, toc, title = [], [], "Spec"
    i, para, list_tag = 0, [], None

    def flush_para():
        nonlocal para
        if para:
            out.append(f"<p>{inline(' '.join(para))}</p>")
            para = []

    def close_list():
        nonlocal list_tag
        if list_tag:
            out.append(f"</{list_tag}>")
            list_tag = None

    while i < len(lines):
        line = lines[i]
        if line.startswith("```"):
            flush_para(); close_list()
            lang = line[3:].strip()
            block = []
            i += 1
            while i < len(lines) and not lines[i].startswith("```"):
                block.append(lines[i]); i += 1
            cls = f' class="language-{html.escape(lang)}"' if lang else ""
            out.append(f"<pre><code{cls}>{html.escape(chr(10).join(block))}</code></pre>")
        elif m := re.match(r"^(#{1,4})\s+(.*)", line):
            flush_para(); close_list()
            level, text = len(m.group(1)), inline(m.group(2))
            anchor = slug(text)
            if level == 1:
                title = re.sub(r"<[^>]+>", "", text)
            else:
                toc.append((level, anchor, text))
            out.append(f'<h{level} id="{anchor}">{text}</h{level}>')
        elif line.lstrip().startswith("|") and i + 1 < len(lines) and re.match(r"^\s*\|[\s:|-]+\|\s*$", lines[i + 1]):
            flush_para(); close_list()
            head = split_row(line)
            i += 2
            rows = []
            while i < len(lines) and lines[i].lstrip().startswith("|"):
                rows.append(split_row(lines[i])); i += 1
            out.append("<table><thead><tr>" + "".join(f"<th>{inline(c)}</th>" for c in head) + "</tr></thead><tbody>")
            out.extend("<tr>" + "".join(f"<td>{inline(c)}</td>" for c in r) + "</tr>" for r in rows)
            out.append("</tbody></table>")
            continue
        elif m := re.match(r"^\s*([-*]|\d+\.)\s+(.*)", line):
            flush_para()
            tag = "ol" if m.group(1)[0].isdigit() else "ul"
            if list_tag != tag:
                close_list(); out.append(f"<{tag}>"); list_tag = tag
            out.append(f"<li>{inline(m.group(2))}</li>")
        elif not line.strip():
            flush_para(); close_list()
        else:
            close_list(); para.append(line.strip())
        i += 1
    flush_para(); close_list()
    return title, "\n".join(out), toc


def main() -> None:
    if len(sys.argv) not in (2, 3):
        sys.exit("usage: md2html.py input.md [output.html]")
    src = Path(sys.argv[1])
    dst = Path(sys.argv[2]) if len(sys.argv) == 3 else src.with_suffix(".html")
    title, body, toc = render(src.read_text(encoding="utf-8"))
    nav = "".join(f'<a class="h{lvl}" href="#{a}">{t}</a>' for lvl, a, t in toc if lvl <= 3)
    page = (f'<!doctype html><html lang="vi"><head><meta charset="utf-8">'
            f'<meta name="viewport" content="width=device-width,initial-scale=1">'
            f"<title>{html.escape(title)}</title><style>{CSS}</style></head><body>"
            f'<div class="layout"><nav>{nav}</nav><main>{body}</main></div><script>{JS}</script></body></html>')
    dst.write_text(page, encoding="utf-8")
    print(dst)


if __name__ == "__main__":
    main()
