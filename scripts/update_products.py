#!/usr/bin/env python3
"""Build Sage/Resources/products.sqlite.zlib from the Open Food Facts export.

Keeps every UK product that has a barcode, a name and complete per-100 g
nutrition (kcal, protein, carbs, fat). It also drops rows whose calories
don't roughly match 4p + 4c + 9f, which are usually data-entry errors.

Usage (from the repo root):
    python3 scripts/update_products.py              # download + build (~1.5 GB stream)
    python3 scripts/update_products.py --jsonl F    # build from an earlier filtered file

The CSV export is streamed, so nothing large is written to disk.
Data: Open Food Facts contributors, ODbL (https://opendatacommons.org/licenses/odbl/1-0/).
"""
import argparse, csv, gzip, io, json, os, sqlite3, sys, tempfile, time, unicodedata, urllib.request, zlib

EXPORT = "https://static.openfoodfacts.org/data/en.openfoodfacts.org.products.csv.gz"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, "Sage", "Resources")


def num(s):
    try:
        v = float(s)
        return v if v == v else None
    except (TypeError, ValueError):
        return None


def filter_export(stream):
    """Yield [code, name, brand, pack, kcal, p, c, f, serving, scans] for good UK rows, deduped by barcode."""
    csv.field_size_limit(1 << 30)
    r = csv.reader(stream, delimiter="\t", quoting=csv.QUOTE_NONE)
    hdr = next(r)
    ix = {h: i for i, h in enumerate(hdr)}

    def g(row, k):
        i = ix[k]
        return row[i] if i < len(row) else ""

    best = {}
    for row in r:
        if "en:united-kingdom" not in g(row, "countries_tags"):
            continue
        code = g(row, "code").strip()
        if not code.isdigit() or not 8 <= len(code) <= 14:
            continue
        name = (g(row, "product_name") or g(row, "abbreviated_product_name")).strip()
        if not name:
            continue
        kcal = num(g(row, "energy-kcal_100g"))
        if kcal is None:
            kj = num(g(row, "energy_100g"))
            kcal = kj / 4.184 if kj is not None else None
        p, c, f = (num(g(row, k)) for k in ("proteins_100g", "carbohydrates_100g", "fat_100g"))
        if None in (kcal, p, c, f) or not 0 <= kcal <= 900 or not all(0 <= x <= 100 for x in (p, c, f)) or p + c + f > 105:
            continue
        if abs(kcal - (4 * p + 4 * c + 9 * f)) > max(60, 0.35 * kcal):
            continue
        serving = num(g(row, "serving_quantity")) or 0
        if not 0 < serving <= 2000:
            serving = 0
        mod = int(num(g(row, "last_modified_t")) or 0)
        rec = [code, name[:120], g(row, "brands").split(",")[0].strip()[:60], g(row, "quantity").strip()[:30],
               round(kcal), round(p, 1), round(c, 1), round(f, 1), round(serving),
               int(num(g(row, "unique_scans_n")) or 0), mod]
        key = code.lstrip("0")
        if key not in best or mod > best[key][10]:
            best[key] = rec
    return [rec[:10] for rec in best.values()]


def fold(s):
    """Lowercase and strip accents, so 'creme' matches 'Crème'."""
    return "".join(ch for ch in unicodedata.normalize("NFKD", s.lower()) if not unicodedata.combining(ch))


def build(rows, out_zlib, out_meta):
    # Merge the original hand-picked list (scripts/off-uk.json) so none of it is lost.
    curated = os.path.join(ROOT, "scripts", "off-uk.json")
    if os.path.exists(curated):
        seen = {r[0].lstrip("0") for r in rows}
        for r in json.load(open(curated)):
            if r[0].lstrip("0") not in seen:
                rows.append(r[:9] + [0])

    # Most-scanned first: searches stop at LIMIT, so popular products come back first and fast.
    rows.sort(key=lambda r: -r[9])
    tmp = tempfile.NamedTemporaryFile(suffix=".sqlite", delete=False).name
    db = sqlite3.connect(tmp)
    db.executescript("""
        PRAGMA page_size = 4096;
        CREATE TABLE products(
            code TEXT NOT NULL, norm TEXT NOT NULL, name TEXT NOT NULL, brand TEXT, pack TEXT,
            kcal REAL, p REAL, c REAL, f REAL, serving REAL, search TEXT NOT NULL);
    """)
    db.executemany(
        "INSERT INTO products VALUES (?,?,?,?,?,?,?,?,?,?,?)",
        [(r[0], r[0].lstrip("0"), r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], fold(r[1] + " " + r[2])) for r in rows],
    )
    db.execute("CREATE INDEX products_norm ON products(norm)")
    db.commit()
    db.execute("VACUUM")
    db.close()

    raw = open(tmp, "rb").read()
    os.unlink(tmp)
    co = zlib.compressobj(9, zlib.DEFLATED, -15)  # raw DEFLATE, as NSData.decompressed(using: .zlib) expects
    packed = co.compress(raw) + co.flush()
    open(out_zlib, "wb").write(packed)
    meta = {"version": time.strftime("%Y%m%d%H%M%S"), "count": len(rows), "bytes": len(raw), "source": EXPORT}
    json.dump(meta, open(out_meta, "w"), indent=2)
    print(f"{len(rows):,} products · sqlite {len(raw) / 1e6:.1f} MB · compressed {len(packed) / 1e6:.1f} MB", file=sys.stderr)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--jsonl", help="use a filtered JSON-lines file instead of downloading")
    args = ap.parse_args()
    if args.jsonl:
        rows = [json.loads(l) for l in open(args.jsonl)]
    else:
        req = urllib.request.Request(EXPORT, headers={"User-Agent": "SageFoodTracker/1.0 (product database build)"})
        with urllib.request.urlopen(req) as resp:
            rows = filter_export(io.TextIOWrapper(gzip.GzipFile(fileobj=resp), encoding="utf-8", errors="replace"))
    build(rows, os.path.join(RES, "products.sqlite.zlib"), os.path.join(RES, "products-meta.json"))


if __name__ == "__main__":
    main()
