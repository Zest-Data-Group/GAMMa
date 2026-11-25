"""Builds upload_excel_date_cells.xlsx: a minimal workbook whose Collection Date
column holds REAL Excel date cells (numeric serials with date format 14), which
is what Excel produces when it opens a CSV and saves it as .xlsx. Row 3 keeps a
text date ("2011") to show text cells are left alone. Standard library only.

    python3 tests/testthat/fixtures/make_xlsx_date_fixture.py
"""
import os, zipfile

HEADERS = ["Accession Number", "Taxon Name", "Current Germplasm Type", "Collection Date",
           "Latitude", "Longitude", "Locality", "Collector"]
# 40769 = 2011-08-14, 40758 = 2011-08-03 (Excel 1900 date system)
ROWS = [
    ["574679236", "Magnolia fraseri Walter", "G", 40769, 35.70725, -82.250556, "North Carolina", "Unwin, Robert"],
    ["574733189", "Magnolia fraseri Walter", "H", 40758, 35.140667, -82.706111, "North Carolina", "Scott, Lesley"],
    ["574733190", "Magnolia fraseri Walter", "H", "2011", 35.2, -82.8, "North Carolina", "Scott, Lesley"],
]

def col(i):
    return "ABCDEFGHIJKLMNOPQRSTUVWXYZ"[i]

def cell(r, c, v, date=False):
    ref = f"{col(c)}{r}"
    if isinstance(v, str):
        v = v.replace("&", "&amp;").replace("<", "&lt;")
        return f'<c r="{ref}" t="inlineStr"><is><t>{v}</t></is></c>'
    style = ' s="1"' if date else ""
    return f'<c r="{ref}"{style}><v>{v}</v></c>'

rows = ['<row r="1">' + "".join(cell(1, i, h) for i, h in enumerate(HEADERS)) + "</row>"]
for n, row in enumerate(ROWS, start=2):
    rows.append(f'<row r="{n}">' + "".join(cell(n, i, v, date=(i == 3)) for i, v in enumerate(row)) + "</row>")

NS = 'xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"'
files = {
    "[Content_Types].xml": '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>',
    "_rels/.rels": '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>',
    "xl/workbook.xml": f'<?xml version="1.0" encoding="UTF-8"?><workbook {NS} xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Sheet1" sheetId="1" r:id="rId1"/></sheets></workbook>',
    "xl/_rels/workbook.xml.rels": '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>',
    "xl/styles.xml": f'<?xml version="1.0" encoding="UTF-8"?><styleSheet {NS}><fonts count="1"><font/></fonts><fills count="1"><fill/></fills><borders count="1"><border/></borders><cellStyleXfs count="1"><xf/></cellStyleXfs><cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="14" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/></cellXfs></styleSheet>',
    "xl/worksheets/sheet1.xml": f'<?xml version="1.0" encoding="UTF-8"?><worksheet {NS}><sheetData>' + "".join(rows) + "</sheetData></worksheet>",
}
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "upload_excel_date_cells.xlsx")
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for name, body in files.items():
        z.writestr(zipfile.ZipInfo(name, date_time=(2026, 11, 25, 0, 0, 0)), body)
print("wrote", out)
