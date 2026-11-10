#!/usr/bin/env python3
"""Build a local, searchable index of Apple's Objective-C API reference.

Apple publishes the data behind developer.apple.com as DocC JSON, which is
where Dash's Apple API Reference docset comes from too:

    /tutorials/data/documentation/technologies.json   the list of frameworks
    /tutorials/data/index/<framework>                 a framework's symbol tree
    /tutorials/data/documentation/<path>.json         one symbol's page

The symbol tree carries a separate "occ" branch whose titles are real
Objective-C selectors ("- webView:didFinishNavigation:"), which is what makes
a selector index possible at all.  Pages are Swift-first: an "occ" variant is
obtained by applying the RFC 6902 patches in variantOverrides.

Subcommands:

    index                  crawl every framework's symbol tree      (~5 min)
    abstracts [FW ...]     fill in one-line abstracts per framework
    page PATH              fetch and store one symbol's full page
    search QUERY           full-text search, for checking the build
    lookup SELECTOR        exact selector lookup, as Emacs does it
    stats                  what the database currently holds

The database is plain SQLite with FTS5; see SCHEMA below.
"""

import argparse
import concurrent.futures as futures
import gzip
import io
import json
import os
import re
import sqlite3
import sys
import time
import urllib.error
import urllib.request

BASE = "https://developer.apple.com/tutorials/data"
UA = "objc-docs/1.0 (personal Emacs documentation index)"
DB_DEFAULT = os.path.expanduser("~/.emacs.d/objc-docs/apple-objc.sqlite")

# Tree node types that own the symbols nested under them.
CONTAINER_KINDS = {"class", "protocol", "enum", "struct", "union", "typealias",
                   "category", "interface"}
# Tree node types that are not symbols at all.
SKIP_KINDS = {"groupMarker", "article", "sampleCode", "overview", "project",
              "tutorial", "learn", "resources"}

SCHEMA = """
PRAGMA journal_mode = WAL;

CREATE TABLE IF NOT EXISTS meta (
    key   TEXT PRIMARY KEY,
    value TEXT
);

CREATE TABLE IF NOT EXISTS framework (
    name       TEXT PRIMARY KEY,   -- 'WebKit'
    slug       TEXT UNIQUE,        -- 'webkit', as it appears in URLs
    symbols    INTEGER DEFAULT 0,
    indexed_at INTEGER,
    abstracts_at INTEGER
);

CREATE TABLE IF NOT EXISTS symbol (
    id        INTEGER PRIMARY KEY,
    name      TEXT NOT NULL,       -- 'webView:didFinishNavigation:'
    marker    TEXT,                -- '-', '+', or NULL for non-methods
    kind      TEXT NOT NULL,       -- method | property | class | protocol | ...
    owner     TEXT,                -- 'WKNavigationDelegate'
    framework TEXT NOT NULL,       -- 'WebKit'
    path      TEXT NOT NULL,       -- '/documentation/webkit/...'
    abstract  TEXT,                -- one-line summary, filled by `abstracts`
    words     TEXT,                -- 'web View did Finish Navigation', for FTS
    UNIQUE (name, owner, path)
);
CREATE INDEX IF NOT EXISTS symbol_name_idx ON symbol (name);
CREATE INDEX IF NOT EXISTS symbol_path_idx ON symbol (path);
CREATE INDEX IF NOT EXISTS symbol_owner_idx ON symbol (owner);

-- One row per symbol page actually fetched.  Kept apart from `symbol` so the
-- index stays cheap to rebuild while cached pages survive.
CREATE TABLE IF NOT EXISTS page (
    path        TEXT PRIMARY KEY,
    fetched_at  INTEGER,
    title       TEXT,
    role        TEXT,              -- 'Instance Method'
    platforms   TEXT,
    abstract    TEXT,
    declaration TEXT,
    parameters  TEXT,
    discussion  TEXT,
    url         TEXT               -- the developer.apple.com page
);

CREATE VIRTUAL TABLE IF NOT EXISTS symbol_fts USING fts5 (
    name, words, owner, framework, abstract,
    content = 'symbol', content_rowid = 'id',
    prefix = '2 3 4'
);

CREATE VIRTUAL TABLE IF NOT EXISTS page_fts USING fts5 (
    path UNINDEXED, title, declaration, discussion, parameters,
    prefix = '2 3 4'
);
"""


# --------------------------------------------------------------------------
# HTTP

class Fetcher:
    """A small, polite HTTP client: gzip, retries, and a shared timeout."""

    def __init__(self, timeout=60, retries=3):
        self.timeout = timeout
        self.retries = retries

    def get_json(self, url):
        last = None
        for attempt in range(self.retries):
            try:
                req = urllib.request.Request(
                    url, headers={"User-Agent": UA, "Accept-Encoding": "gzip",
                                  "Accept": "application/json"})
                with urllib.request.urlopen(req, timeout=self.timeout) as r:
                    raw = r.read()
                    if r.headers.get("Content-Encoding") == "gzip":
                        raw = gzip.decompress(raw)
                    return json.loads(raw.decode("utf-8"))
            except urllib.error.HTTPError as e:
                if e.code == 404:
                    return None
                last = e
            except Exception as e:  # noqa: BLE001 - network, retry everything
                last = e
            time.sleep(1.5 * (attempt + 1))
        raise RuntimeError(f"{url}: {last}")


# --------------------------------------------------------------------------
# DocC helpers

def unescape_pointer(token):
    return token.replace("~1", "/").replace("~0", "~")


def apply_patch(doc, ops):
    """Apply the RFC 6902 subset DocC uses (add / replace / remove)."""
    for op in ops:
        path = op.get("path", "")
        if not path:
            continue
        tokens = [unescape_pointer(t) for t in path.split("/")[1:]]
        target, key = doc, None
        for i, token in enumerate(tokens):
            last = i == len(tokens) - 1
            if isinstance(target, list):
                if token == "-":
                    key = len(target)
                else:
                    try:
                        key = int(token)
                    except ValueError:
                        target = None
                        break
            else:
                key = token
            if last:
                break
            try:
                target = target[key]
            except (KeyError, IndexError, TypeError):
                target = None
                break
        if target is None:
            continue
        action = op.get("op")
        try:
            if action == "remove":
                del target[key]
            elif action in ("add", "replace"):
                if isinstance(target, list) and action == "add":
                    target.insert(key, op.get("value"))
                else:
                    target[key] = op.get("value")
        except (KeyError, IndexError, TypeError):
            continue
    return doc


def objc_variant(doc):
    """Return DOC rewritten as its Objective-C variant, when it has one."""
    for override in doc.get("variantOverrides") or []:
        traits = override.get("traits") or []
        if any(t.get("interfaceLanguage") == "occ" for t in traits):
            return apply_patch(doc, override.get("patch") or [])
    return doc


def inline_text(nodes):
    """Flatten DocC inline content to plain text."""
    out = []
    for n in nodes or []:
        if isinstance(n, str):
            out.append(n)
            continue
        t = n.get("type")
        if t in ("text", "codeVoice"):
            out.append(n.get("text", n.get("code", "")))
        elif t == "reference":
            out.append(n.get("title") or n.get("identifier", "").rsplit("/", 1)[-1])
        elif t in ("emphasis", "strong", "newTerm", "inlineHead"):
            out.append(inline_text(n.get("inlineContent")))
        elif t == "image":
            pass
        else:
            out.append(inline_text(n.get("inlineContent")))
    return "".join(out)


def block_text(blocks, depth=0):
    """Flatten DocC block content to plain text paragraphs."""
    out = []
    for b in blocks or []:
        t = b.get("type")
        if t == "paragraph":
            out.append(inline_text(b.get("inlineContent")))
        elif t == "codeListing":
            out.append("\n".join(b.get("code") or []))
        elif t in ("unorderedList", "orderedList"):
            for i, item in enumerate(b.get("items") or [], 1):
                bullet = "* " if t == "unorderedList" else f"{i}. "
                out.append(bullet + block_text(item.get("content"), depth + 1))
        elif t == "heading":
            # DocC labels the discussion section with a heading of its own;
            # the reader already knows which section this is.
            text = b.get("text", "")
            if text not in ("Discussion", "Overview"):
                out.append(text)
        elif t == "aside":
            out.append(f"{b.get('name', 'Note')}: " + block_text(b.get("content"), depth + 1))
        elif t == "termList":
            for item in b.get("items") or []:
                term = inline_text((item.get("term") or {}).get("inlineContent"))
                out.append(f"{term}: " + block_text(item.get("definition", {}).get("content"), depth + 1))
        elif "content" in b:
            out.append(block_text(b.get("content"), depth + 1))
    return "\n\n".join(x for x in out if x)


def declaration_text(section):
    parts = []
    for decl in section.get("declarations") or []:
        parts.append("".join(tok.get("text", "") for tok in decl.get("tokens") or []))
    return "\n".join(parts)


def parse_page(doc):
    """Pull the fields we store out of an Objective-C render JSON document."""
    meta = doc.get("metadata") or {}
    platforms = ", ".join(
        p.get("name", "") + (
            " " + p["introducedAt"] + "+" if p.get("introducedAt") else "")
        for p in meta.get("platforms") or [])
    declaration = parameters = discussion = ""
    for section in doc.get("primaryContentSections") or []:
        kind = section.get("kind")
        if kind == "declarations" or "declarations" in section:
            declaration = declaration_text(section)
        elif kind == "parameters":
            rows = []
            for p in section.get("parameters") or []:
                rows.append(f"{p.get('name', '')}: " + block_text(p.get("content")))
            parameters = "\n".join(rows)
        elif kind == "content":
            discussion = block_text(section.get("content"))
    url = None
    ident = (doc.get("identifier") or {}).get("url", "")
    for variant in doc.get("variants") or []:
        if any(t.get("interfaceLanguage") == "occ" for t in variant.get("traits") or []):
            paths = variant.get("paths") or []
            if paths:
                url = f"https://developer.apple.com{paths[0]}?language=objc"
    if not url and ident:
        url = "https://developer.apple.com/documentation/" + ident.split("/documentation/")[-1]
    return {
        "title": meta.get("title"),
        "role": meta.get("roleHeading"),
        "platforms": platforms,
        "abstract": inline_text(doc.get("abstract")),
        "declaration": declaration,
        "parameters": parameters,
        "discussion": discussion,
        "url": url,
    }


# --------------------------------------------------------------------------
# Database

WORD_RE = re.compile(r"[A-Z]+(?![a-z])|[A-Z][a-z]+|[a-z]+|[0-9]+")


def split_words(name, owner=None):
    """Split an identifier into words: FTS tokenizes camel case as one token.

    'webView:didFinishNavigation:' -> 'web View did Finish Navigation', so a
    search for 'finish navigation' finds it.  The owning class is split in
    too, which is how 'navigation delegate' reaches WKNavigationDelegate.
    """
    parts = WORD_RE.findall(name or "")
    if owner:
        parts += WORD_RE.findall(owner)
    return " ".join(parts)


def connect(path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    db = sqlite3.connect(path)
    db.executescript(SCHEMA)
    migrate(db)
    return db


def migrate(db):
    """Bring a database built by an older version up to the current schema."""
    columns = {r[1] for r in db.execute("PRAGMA table_info(symbol)")}
    if "words" not in columns:
        db.execute("ALTER TABLE symbol ADD COLUMN words TEXT")
        db.commit()
    fts = {r[1] for r in db.execute("PRAGMA table_info(symbol_fts)")}
    if "words" not in fts:
        db.executescript(
            "DROP TABLE IF EXISTS symbol_fts;"
            "CREATE VIRTUAL TABLE symbol_fts USING fts5 ("
            " name, words, owner, framework, abstract,"
            " content = 'symbol', content_rowid = 'id', prefix = '2 3 4');")
        db.commit()


def set_meta(db, key, value):
    db.execute("INSERT INTO meta(key, value) VALUES(?, ?) "
               "ON CONFLICT(key) DO UPDATE SET value = excluded.value",
               (key, str(value)))


# --------------------------------------------------------------------------
# index

def framework_list(fetcher):
    """Return [(display name, url slug)] for every documented framework."""
    doc = fetcher.get_json(f"{BASE}/documentation/technologies.json")
    out = {}
    for ref in (doc.get("references") or {}).values():
        url = ref.get("url") or ""
        if ref.get("role") != "collection" or not url.startswith("/documentation/"):
            continue
        slug = url[len("/documentation/"):]
        if "/" in slug or not slug:
            continue
        out[slug] = ref.get("title") or slug
    return sorted((name, slug) for slug, name in out.items())


def walk_tree(nodes, owner=None):
    """Yield (node, owner) for every symbol node in an occ index tree."""
    for node in nodes or []:
        kind = node.get("type")
        title = node.get("title") or ""
        children = node.get("children")
        if kind not in SKIP_KINDS and node.get("path"):
            yield node, owner
        # A container becomes the owner of everything nested inside it, but
        # group markers and collections are only scaffolding and are skipped.
        next_owner = title if kind in CONTAINER_KINDS else owner
        if children:
            yield from walk_tree(children, next_owner)


def index_framework(fetcher, name, slug):
    doc = fetcher.get_json(f"{BASE}/index/{slug}")
    if not doc:
        return name, slug, []
    occ = (doc.get("interfaceLanguages") or {}).get("occ") or []
    rows, seen = [], set()
    for node, owner in walk_tree(occ):
        title = (node.get("title") or "").strip()
        if not title:
            continue
        marker = None
        if title[:2] in ("- ", "+ "):
            marker, title = title[0], title[2:].strip()
        key = (title, owner, node["path"])
        if key in seen:
            continue
        seen.add(key)
        rows.append((title, marker, node.get("type") or "symbol", owner, name,
                     node["path"], split_words(title, owner)))
    return name, slug, rows


def cmd_index(args, db):
    fetcher = Fetcher()
    frameworks = framework_list(fetcher)
    if args.frameworks:
        wanted = {f.lower() for f in args.frameworks}
        frameworks = [(n, s) for n, s in frameworks
                      if n.lower() in wanted or s in wanted]
    print(f"indexing {len(frameworks)} frameworks", file=sys.stderr)
    total = 0
    done = 0
    with futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
        jobs = [pool.submit(index_framework, fetcher, n, s) for n, s in frameworks]
        for job in futures.as_completed(jobs):
            try:
                name, slug, rows = job.result()
            except Exception as e:  # noqa: BLE001
                print(f"  !! {e}", file=sys.stderr)
                continue
            done += 1
            if rows:
                db.executemany(
                    "INSERT OR IGNORE INTO symbol"
                    "(name, marker, kind, owner, framework, path, words)"
                    " VALUES(?, ?, ?, ?, ?, ?, ?)", rows)
                db.execute(
                    "INSERT INTO framework(name, slug, symbols, indexed_at)"
                    " VALUES(?, ?, ?, ?) ON CONFLICT(name) DO UPDATE SET"
                    " slug = excluded.slug, symbols = excluded.symbols,"
                    " indexed_at = excluded.indexed_at",
                    (name, slug, len(rows), int(time.time())))
                db.commit()
            total += len(rows)
            if done % 25 == 0 or not rows:
                print(f"  [{done}/{len(frameworks)}] {name}: {len(rows)} symbols"
                      f" (total {total})", file=sys.stderr)
    set_meta(db, "indexed_at", int(time.time()))
    db.commit()
    rebuild_fts(db)
    print(f"indexed {total} Objective-C symbols", file=sys.stderr)


def rebuild_fts(db):
    db.execute("INSERT INTO symbol_fts(symbol_fts) VALUES('rebuild')")
    db.commit()


# --------------------------------------------------------------------------
# abstracts

def cmd_abstracts(args, db):
    fetcher = Fetcher()
    if args.frameworks:
        names = []
        for f in args.frameworks:
            row = db.execute("SELECT name FROM framework WHERE lower(name) = ?"
                             " OR slug = ?", (f.lower(), f.lower())).fetchone()
            names.append(row[0] if row else f)
    else:
        names = [r[0] for r in db.execute(
            "SELECT name FROM framework ORDER BY symbols DESC")]
    for name in names:
        containers = [r[0] for r in db.execute(
            "SELECT DISTINCT path FROM symbol WHERE framework = ? AND kind IN"
            " ('class', 'protocol', 'enum', 'struct', 'union', 'typealias')",
            (name,))]
        if not containers:
            continue
        print(f"{name}: {len(containers)} container pages", file=sys.stderr)
        filled = 0
        with futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
            jobs = {pool.submit(fetcher.get_json,
                                f"{BASE}{p}.json"): p
                    for p in containers}
            for job in futures.as_completed(jobs):
                try:
                    doc = job.result()
                except Exception as e:  # noqa: BLE001
                    print(f"  !! {e}", file=sys.stderr)
                    continue
                if not doc:
                    continue
                doc = objc_variant(doc)
                updates = []
                for ref in (doc.get("references") or {}).values():
                    url, abstract = ref.get("url"), ref.get("abstract")
                    if url and abstract:
                        updates.append((inline_text(abstract), url))
                if updates:
                    cur = db.executemany(
                        "UPDATE symbol SET abstract = ? WHERE path = ?"
                        " AND abstract IS NULL", updates)
                    filled += cur.rowcount or 0
                    db.commit()
        db.execute("UPDATE framework SET abstracts_at = ? WHERE name = ?",
                   (int(time.time()), name))
        db.commit()
        print(f"  filled {filled} abstracts", file=sys.stderr)
    rebuild_fts(db)


# --------------------------------------------------------------------------
# page

def store_page(db, path, doc):
    fields = parse_page(objc_variant(doc))
    db.execute(
        "INSERT INTO page(path, fetched_at, title, role, platforms, abstract,"
        " declaration, parameters, discussion, url)"
        " VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
        " ON CONFLICT(path) DO UPDATE SET fetched_at = excluded.fetched_at,"
        " title = excluded.title, role = excluded.role,"
        " platforms = excluded.platforms, abstract = excluded.abstract,"
        " declaration = excluded.declaration, parameters = excluded.parameters,"
        " discussion = excluded.discussion, url = excluded.url",
        (path, int(time.time()), fields["title"], fields["role"],
         fields["platforms"], fields["abstract"], fields["declaration"],
         fields["parameters"], fields["discussion"], fields["url"]))
    db.execute("DELETE FROM page_fts WHERE path = ?", (path,))
    db.execute("INSERT INTO page_fts(path, title, declaration, discussion,"
               " parameters) VALUES(?, ?, ?, ?, ?)",
               (path, fields["title"], fields["declaration"],
                fields["discussion"], fields["parameters"]))
    if fields["abstract"]:
        db.execute("UPDATE symbol SET abstract = ? WHERE path = ?"
                   " AND abstract IS NULL", (fields["abstract"], path))
    db.commit()
    return fields


def cmd_page(args, db):
    fetcher = Fetcher()
    for path in args.paths:
        doc = fetcher.get_json(f"{BASE}{path}.json")
        if not doc:
            print(f"{path}: not found", file=sys.stderr)
            continue
        fields = store_page(db, path, doc)
        if args.json:
            print(json.dumps(fields, indent=1))
        else:
            print(f"{fields['title']}  [{fields['role']}]")
            print(f"  {fields['abstract']}")
            print(f"  {fields['declaration']}")


def cmd_prefetch(args, db):
    fetcher = Fetcher()
    paths = [r[0] for r in db.execute(
        "SELECT s.path FROM symbol s LEFT JOIN page p USING (path)"
        " WHERE s.framework = ? AND p.path IS NULL GROUP BY s.path",
        (args.framework,))]
    print(f"{args.framework}: {len(paths)} pages to fetch", file=sys.stderr)
    done = 0
    with futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
        jobs = {pool.submit(fetcher.get_json, f"{BASE}{p}.json"): p
                for p in paths}
        for job in futures.as_completed(jobs):
            path = jobs[job]
            try:
                doc = job.result()
            except Exception as e:  # noqa: BLE001
                print(f"  !! {path}: {e}", file=sys.stderr)
                continue
            if doc:
                store_page(db, path, doc)
            done += 1
            if done % 100 == 0:
                print(f"  {done}/{len(paths)}", file=sys.stderr)


# --------------------------------------------------------------------------
# queries

def cmd_rebuild(args, db):
    """Recompute derived columns and the full-text index, without any network."""
    rows = db.execute("SELECT id, name, owner FROM symbol"
                      " WHERE words IS NULL").fetchall()
    print(f"filling words for {len(rows)} symbols", file=sys.stderr)
    db.executemany("UPDATE symbol SET words = ? WHERE id = ?",
                   [(split_words(n, o), i) for i, n, o in rows])
    db.commit()
    print("rebuilding the full-text index", file=sys.stderr)
    rebuild_fts(db)
    print("done", file=sys.stderr)


def cmd_lookup(args, db):
    rows = db.execute(
        "SELECT name, marker, kind, owner, framework, path, abstract"
        " FROM symbol WHERE name = ? ORDER BY framework, owner", (args.selector,))
    for name, marker, kind, owner, framework, path, abstract in rows:
        print(f"{(marker or ' ')} {owner or '-'}.{name}  [{kind}, {framework}]")
        if abstract:
            print(f"    {abstract}")
        print(f"    {path}")


def cmd_search(args, db):
    rows = db.execute(
        "SELECT s.name, s.owner, s.kind, s.framework, s.abstract"
        " FROM symbol_fts f JOIN symbol s ON s.id = f.rowid"
        " WHERE symbol_fts MATCH ? ORDER BY rank LIMIT ?",
        (args.query, args.limit))
    for name, owner, kind, framework, abstract in rows:
        print(f"{owner or '-'}.{name}  [{kind}, {framework}]")
        if abstract:
            print(f"    {abstract}")


def cmd_stats(args, db):
    def one(sql):
        return db.execute(sql).fetchone()[0]
    counts = [
        ("frameworks", "SELECT count(*) FROM framework"),
        ("symbols", "SELECT count(*) FROM symbol"),
        ("  with abstract", "SELECT count(*) FROM symbol WHERE abstract IS NOT NULL"),
        ("  methods", "SELECT count(*) FROM symbol WHERE kind = 'method'"),
        ("  properties", "SELECT count(*) FROM symbol WHERE kind = 'property'"),
        ("  classes", "SELECT count(*) FROM symbol WHERE kind = 'class'"),
        ("  protocols", "SELECT count(*) FROM symbol WHERE kind = 'protocol'"),
        ("cached pages", "SELECT count(*) FROM page"),
    ]
    for label, sql in counts:
        print(f"{label + ':':20} {one(sql)}")
    row = db.execute("SELECT value FROM meta WHERE key = 'indexed_at'").fetchone()
    if row:
        print(f"indexed:           {time.strftime('%Y-%m-%d %H:%M', time.localtime(int(row[0])))}")
    print("\nlargest frameworks:")
    for name, n in db.execute("SELECT name, symbols FROM framework"
                              " ORDER BY symbols DESC LIMIT 8"):
        print(f"  {name:28} {n}")


# --------------------------------------------------------------------------

def main():
    # The subparsers repeat these so they work on either side of the
    # subcommand; SUPPRESS keeps their defaults from overwriting a value the
    # main parser already took from the left-hand side.
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--db", default=argparse.SUPPRESS)
    common.add_argument("-j", "--jobs", type=int, default=argparse.SUPPRESS)

    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--db", default=DB_DEFAULT)
    ap.add_argument("-j", "--jobs", type=int, default=8)
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("index", parents=[common], help="crawl framework symbol trees")
    p.add_argument("frameworks", nargs="*")
    p.set_defaults(func=cmd_index)

    p = sub.add_parser("abstracts", parents=[common], help="fill in one-line abstracts")
    p.add_argument("frameworks", nargs="*")
    p.set_defaults(func=cmd_abstracts)

    p = sub.add_parser("page", parents=[common], help="fetch and cache full pages")
    p.add_argument("paths", nargs="+")
    p.add_argument("--json", action="store_true")
    p.set_defaults(func=cmd_page)

    p = sub.add_parser("prefetch", parents=[common], help="cache every page of a framework")
    p.add_argument("framework")
    p.set_defaults(func=cmd_prefetch)

    p = sub.add_parser("rebuild", parents=[common],
                       help="recompute derived columns and the FTS index")
    p.set_defaults(func=cmd_rebuild)

    p = sub.add_parser("lookup", parents=[common], help="exact selector lookup")
    p.add_argument("selector")
    p.set_defaults(func=cmd_lookup)

    p = sub.add_parser("search", parents=[common], help="full-text search")
    p.add_argument("query")
    p.add_argument("--limit", type=int, default=20)
    p.set_defaults(func=cmd_search)

    p = sub.add_parser("stats", parents=[common], help="what the database holds")
    p.set_defaults(func=cmd_stats)

    args = ap.parse_args()
    db = connect(os.path.expanduser(args.db))
    try:
        args.func(args, db)
    finally:
        db.close()


if __name__ == "__main__":
    main()
