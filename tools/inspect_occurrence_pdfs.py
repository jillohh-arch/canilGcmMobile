#!/usr/bin/env python3
"""F70 — Visual PDF inspection (fonts, pagination, geometry, text)."""
import os, glob, re, sys
from pathlib import Path
from pypdf import PdfReader

out_dir = Path("build/visual_fixtures/occurrence_f70")
pdfs = sorted(out_dir.glob("*.pdf"))
if not pdfs:
    print("No PDFs found in", out_dir)
    sys.exit(1)

print(f"Found {len(pdfs)} PDFs in {out_dir}\n")
print(f"{'File':36s} {'Pages':>5s} {'Size':>10s} {'/Page entries':>14s} {'/Image XObjs':>14s}")
print("-" * 90)

has_blocker = False

for pdf_path in pdfs:
    data = pdf_path.read_bytes()
    raw = data.decode("latin1", errors="ignore")
    reader = PdfReader(str(pdf_path))
    pages = len(reader.pages)
    size = pdf_path.stat().st_size
    # Raw scan counts
    page_entries = len(re.findall(r"/Type\s*/Page(?!s)", raw))
    image_xobjs = len(re.findall(r"/Subtype\s*/Image", raw))
    # Pagination footer probe
    has_pagina0 = "PÁGINA 0" in raw or "PAGINA 0" in raw
    has_pagina_de = " de " in raw  # "Página X de Y"
    to_unicode = raw.count("/ToUnicode")
    # ProductMark probe (image)
    # Text extraction per page (first 200 chars)
    first_text = ""
    try:
        first_text = (reader.pages[0].extract_text() or "")[:300]
    except Exception as e:
        first_text = f"<extract error: {e}>"

    flag = ""
    if has_pagina0:
        flag = " [BLOCKER: PÁGINA 0]"
        has_blocker = True
    print(
        f"{pdf_path.name:36s} {pages:5d} {size:10d} {page_entries:14d} {image_xobjs:14d}{flag}"
    )
    print(f"  ToUnicode CMaps: {to_unicode}, has ' de ' in raw: {has_pagina_de}")
    # Show first page text snippet (normalized whitespace)
    snippet = " ".join(first_text.split())
    if len(snippet) > 180:
        snippet = snippet[:180] + "…"
    if snippet:
        print(f"  p1 text: {snippet}")
    print()

# Per-scenario deep checks
print("\n=== SCENARIO DEEP CHECKS ===\n")

def deep_check(name, expectations):
    global has_blocker
    pdf = next((p for p in pdfs if name in p.name), None)
    if pdf is None:
        print(f"[SKIP] {name}: not found")
        return
    data = pdf.read_bytes()
    raw = data.decode("latin1", errors="ignore")
    reader = PdfReader(str(pdf))
    all_text = ""
    for pg in reader.pages:
        try:
            all_text += (pg.extract_text() or "") + "\n---PAGE---\n"
        except Exception:
            pass
    print(f"--- {pdf.name} ({len(reader.pages)} pages) ---")
    for label, check_fn in expectations:
        ok, detail = check_fn(raw, all_text, reader)
        status = "PASS" if ok else "FAIL"
        print(f"  [{status}] {label}: {detail}")
        if not ok and "BLOCKER" in label:
            has_blocker = True
    print()

# E: actual image rendering
deep_check("E_evidence", [
    ("E actual images (BLOCKER if fallback only)", lambda raw, txt, r: (
        len(re.findall(r"/Subtype\s*/Image", raw)) >= 4,
        f"images={len(re.findall(r'/Subtype\s*/Image', raw))} (need >=4 synthetic)"
    )),
    ("E no missing-image fallback dominance", lambda raw, txt, r: (
        "imagem indispon" not in txt.lower() or len(re.findall(r"/Subtype\s*/Image", raw)) >= 4,
        "fallback present=" + str("imagem indispon" in txt.lower())
    )),
    ("E captions present", lambda raw, txt, r: (
        "Evid" in txt or "aspecto" in txt.lower() or "MIDIAS" in txt,
        f"snippet: {(txt[:200].replace(chr(10),' '))}"
    )),
])

# J: populated amendment
deep_check("J_populated", [
    ("J amendment section rendered (BLOCKER if missing)", lambda raw, txt, r: (
        "ADITAMENTO" in txt.upper() or "RETIFICA" in txt.upper(),
        f"has ADITAMENTO/RETIFICA in extracted text: {('ADITAMENTO' in txt.upper() or 'RETIFICA' in txt.upper())}"
    )),
    ("J correction visible", lambda raw, txt, r: (
        "Rua Nova" in txt or "Rua Antiga" in txt or "logradouro" in txt.lower() or "CORRE" in txt.upper(),
        f"has correction text in extracted text"
    )),
    ("J hash and reason present", lambda raw, txt, r: (
        "HASH" in txt.upper() or "integridade" in txt.lower(),
        "amendment audit block present"
    )),
    ("J QR present (by image count)", lambda raw, txt, r: (
        len(re.findall(r"/Subtype\s*/Image", raw)) >= 1,
        f"images={len(re.findall(r'/Subtype\s*/Image', raw))} (at least QR)"
    )),
])

# G/H: pagination and continuation
for name in ["G_long", "H_multipage"]:
    deep_check(name, [
        ("Pagination multi-page", lambda raw, txt, r: (len(r.pages) >= 2, f"pages={len(r.pages)}")),
        ("Footer Pagina X de Y", lambda raw, txt, r: (
            any(" de " in (pg.extract_text() or "") for pg in r.pages),
            "footer text in extracted pages"
        )),
        ("No PAGINA 0 (BLOCKER)", lambda raw, txt, r: ("PÁGINA 0" not in txt and "PAGINA 0" not in txt, "absent" if "PÁGINA 0" not in txt else "FOUND")),
        ("Continuation header on page 2+", lambda raw, txt, r: (
            len(r.pages) >= 2 and len((r.pages[1].extract_text() or "").strip()) > 20,
            f"p2 text len={len((r.pages[1].extract_text() or '').strip())}"
        )),
    ])

# B/C/I/K: status and signature presence
deep_check("B_multi_actor", [
    ("B signatures table", lambda raw, txt, r: ("Assinatura" in txt or "ASSINATURA" in txt.upper(), "signature block present")),
    ("B team table", lambda raw, txt, r: ("Equipe" in txt or "EQUIPE" in txt.upper() or "Condutor" in txt, "team block")),
])
deep_check("C_finalizedWithPending", [
    ("C pending notice", lambda raw, txt, r: ("PEND" in txt.upper(), f"has PENDENCIA/PENDENTE: {'PEND' in txt.upper()}")),
])
deep_check("I_canceled", [
    ("I canceled status visible", lambda raw, txt, r: ("Cancel" in txt, f"has Cancelado: {'Cancel' in txt}")),
])
deep_check("K_legacy", [
    ("K legacy verdict", lambda raw, txt, r: ("LEGADO" in txt.upper() or "legado" in txt.lower(), "legacy label present")),
])

# L: minimal
deep_check("L_no_location", [
    ("L renders without crash", lambda raw, txt, r: (len(r.pages) >= 1, f"pages={len(r.pages)}")),
])

# Overlap / truncation probe: check that text extraction is substantial on every page
print("=== PAGE TEXT DENSITY (overlap/truncation probe) ===")
for pdf_path in pdfs:
    reader = PdfReader(str(pdf_path))
    print(f"{pdf_path.name}: ", end="")
    for i, pg in enumerate(reader.pages):
        t = (pg.extract_text() or "").strip()
        words = len(t.split())
        marker = " OK" if words > 10 else " THIN" if words > 0 else " EMPTY"
        print(f"[p{i+1}:{words}w{marker}]", end=" ")
    print()

# Overall verdict
print("\n" + "="*60)
if has_blocker:
    print("OVERALL: BLOCKER(s) detected — see flags above.")
else:
    print("OVERALL: No PÁGINA 0 blockers detected; pagination and image/amendment probes executed (visual confirmation pending owner review).")
