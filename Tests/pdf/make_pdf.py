# Genera un extracto de prueba con la misma estructura que los de ING (JasperReports):
# cada celda es un texto suelto, se dibuja columna a columna, el € va aparte y hay texto vertical en el margen.
import sys, random
from reportlab.pdfgen import canvas
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
pdfmetrics.registerFont(TTFont("F", sys.argv[2]))
c = canvas.Canvas(sys.argv[1], pagesize=(595, 842))
H = 842
random.seed(1)
rows = []
saldo = 1000.0
for i in range(40):
    d = f"{1 + i // 2:02d}/09"
    amt = round(random.choice([-1, -1, -1, 1]) * random.uniform(1, 150), 2)
    saldo += amt
    rows.append((d, d, random.choice(["Pago MERCADONA LA MONTA", "Traspaso emitido", "Pago PLAYSTATION ***5027", "Transferencia BIZUM recibida", "Pago E.S CEPSA SAN FERNANDO"]), amt, saldo))
def eur(v): return f"{v:,.2f}".replace(",", "X").replace(".", ",").replace("X", ".")
c.setFont("F", 9)
c.drawString(55, H - 120, "Septiembre 2026     Saldo final a 30/09/2026")
c.drawString(55, H - 150, "Cuenta NÓMINA - IBAN: ES00 0000 0000 0000 0000 0000      Saldo final  1,00€")
c.saveState(); c.translate(30, 100); c.rotate(90); c.setFont("F", 7)
c.drawString(0, 0, "ING BANK NV, Sucursal en España, C/ Vía de los Poblados, 1F, 28033 Madrid, CIF W0037986G, inscrita en el Registro Mercantil")
c.restoreState()
c.setFont("F", 9)
y0 = H - 180
for col, x in ((0, 55), (1, 130), (2, 196)):
    for i, r in enumerate(rows):
        c.drawString(x, y0 - 13 * i, r[col])
for i, r in enumerate(rows):
    c.drawRightString(461, y0 - 13 * i, eur(r[3]))
    c.drawString(464, y0 - 13 * i, "€")
for i, r in enumerate(rows):
    c.drawRightString(556, y0 - 13 * i, eur(r[4]))
    c.drawString(559, y0 - 13 * i, "€")
c.showPage(); c.save()
print(len(rows))
