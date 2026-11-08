using System.Globalization;
using System.Text;

namespace Cinach;

internal static class TicketPdf
{
    private const int Width = 360;
    private const int Height = 590;

    public static byte[] Create(Dictionary<string, object?> t)
    {
        string Read(string key) => Convert.ToString(t.GetValueOrDefault(key), CultureInfo.InvariantCulture) ?? "";
        string Fecha()
        {
            var v = t.GetValueOrDefault("fechaFuncion");
            return v is DateTime dt ? dt.ToString("dd/MM/yyyy", CultureInfo.GetCultureInfo("es-MX")) : Read("fechaFuncion").Split(' ')[0];
        }
        string Hora()
        {
            var v = t.GetValueOrDefault("hora");
            return v is TimeSpan ts ? ts.ToString(@"hh\:mm", CultureInfo.InvariantCulture) : Read("hora");
        }
        string Total()
        {
            var v = t.GetValueOrDefault("total");
            return v is null ? "0.00" : Convert.ToDecimal(v, CultureInfo.InvariantCulture).ToString("N2", CultureInfo.GetCultureInfo("es-MX"));
        }

        var p = new StringBuilder();
        void Rect(int x, int y, int w, int h, string color)
        {
            p.Append(color).Append(" rg\n").Append(x).Append(' ').Append(y).Append(' ').Append(w).Append(' ').Append(h).Append(" re f\n");
        }
        void Text(int x, int y, int size, string color, string value, bool bold = false)
        {
            p.Append("BT ").Append(color).Append(" rg /F").Append(bold ? '2' : '1').Append(' ').Append(size)
                .Append(" Tf 1 0 0 1 ").Append(x).Append(' ').Append(y).Append(" Tm (")
                .Append(Escape(value)).Append(") Tj ET\n");
        }
        string Cut(string s, int max) => s.Length > max ? s[..(max - 3)] + "..." : s;

        Rect(0, 0, Width, Height, "1 1 1");
        Rect(18, 18, Width - 36, Height - 36, "0.98 0.98 0.98");
        Rect(18, Height - 60, Width - 36, 1, "0.35 0.35 0.35");
        Text(30, 548, 20, "0 0 0", "CINACH", true);
        Text(30, 532, 9, "0.25 0.25 0.25", "ENTRADA DE CINE - COMPROBANTE");
        Text(30, 505, 8, "0.35 0.35 0.35", "FOLIO");
        Text(30, 489, 13, "0 0 0", Cut(Read("folio"), 34), true);

        Rect(30, 476, Width - 60, 1, "0.65 0.65 0.65");
        Text(30, 456, 8, "0.35 0.35 0.35", "PELÍCULA");
        var movie = Cut(Read("pelicula").ToUpperInvariant(), 52);
        if (movie.Length <= 29)
            Text(30, 438, 12, "0 0 0", movie, true);
        else
        {
            var at = movie.LastIndexOf(' ', 29);
            if (at < 12) at = 29;
            Text(30, 438, 12, "0 0 0", movie[..at].TrimEnd(), true);
            Text(30, 422, 12, "0 0 0", movie[at..].TrimStart(), true);
        }

        Text(30, 392, 8, "0.35 0.35 0.35", "CINE / SUCURSAL");
        Text(30, 376, 10, "0 0 0", Cut(Read("cine"), 26), true);
        Text(30, 362, 10, "0 0 0", Cut(Read("sucursal"), 38));
        Rect(30, 350, Width - 60, 1, "0.65 0.65 0.65");

        Text(30, 330, 8, "0.35 0.35 0.35", "FECHA");
        Text(30, 315, 10, "0 0 0", Fecha(), true);
        Text(150, 330, 8, "0.35 0.35 0.35", "HORA");
        Text(150, 315, 10, "0 0 0", Hora(), true);
        Text(240, 330, 8, "0.35 0.35 0.35", "SALA");
        Text(240, 315, 10, "0 0 0", Cut(Read("sala"), 10), true);

        Text(30, 288, 8, "0.35 0.35 0.35", "ASIENTOS");
        Text(30, 272, 10, "0 0 0", Cut(Read("asientos"), 34), true);
        Rect(30, 258, Width - 60, 1, "0.65 0.65 0.65");

        Text(30, 236, 8, "0.35 0.35 0.35", "TOTAL");
        Text(30, 216, 18, "0 0 0", "$" + Total() + " MXN", true);

        Text(30, 185, 8, "0.35 0.35 0.35", "REFERENCIA DE PAGO");
        Text(30, 170, 9, "0 0 0", Cut(Read("autorizacion"), 42));
        Rect(30, 156, Width - 60, 1, "0.65 0.65 0.65");

        Text(30, 130, 8, "0.25 0.25 0.25", "Conserva tu folio para futuras consultas.");
        Text(30, 116, 8, "0.25 0.25 0.25", "Comprobante académico emitido por CINACH.");
        Text(30, 102, 8, "0.25 0.25 0.25", "Sin cargos bancarios reales.");
        Text(30, 72, 9, "0 0 0", "CINACH | Comunidad UNACH", true);

        var body = Encoding.ASCII.GetBytes(p.ToString());
        var objects = new[]
        {
            "<< /Type /Catalog /Pages 2 0 R >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            $"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 {Width} {Height}] /Resources << /Font << /F1 4 0 R /F2 5 0 R >> >> /Contents 6 0 R >>",
            "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>",
            "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>",
            $"<< /Length {body.Length} >>\nstream\n{p}endstream"
        };
        using var ms = new MemoryStream();
        void Write(string s)
        {
            var bytes = Encoding.ASCII.GetBytes(s);
            ms.Write(bytes, 0, bytes.Length);
        }
        ms.Write(new byte[] { 37, 80, 68, 70, 45, 49, 46, 52, 10, 37, 226, 227, 207, 211, 10 });
        var offsets = new List<long>();
        for (var i = 0; i < objects.Length; i++)
        {
            offsets.Add(ms.Position);
            Write($"{i + 1} 0 obj\n{objects[i]}\nendobj\n");
        }
        var xref = ms.Position;
        Write($"xref\n0 {objects.Length + 1}\n0000000000 65535 f \n");
        foreach (var off in offsets) Write($"{off:D10} 00000 n \n");
        Write($"trailer\n<< /Size {objects.Length + 1} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n");
        return ms.ToArray();
    }

    private static string Escape(string s)
    {
        var outText = new StringBuilder();
        foreach (var ch in s.Normalize(NormalizationForm.FormC))
        {
            if (ch is '(' or ')' or '\\') outText.Append('\\').Append(ch);
            else if (ch >= ' ' && ch <= '~') outText.Append(ch);
            else if (ch >= '\u00a0' && ch <= '\u00ff') outText.Append('\\').Append(Convert.ToString((int)ch, 8).PadLeft(3, '0'));
            else if (ch is '\u2013' or '\u2014') outText.Append('-');
            else if (ch is '\u2018' or '\u2019') outText.Append("'");
            else if (ch is '\u201c' or '\u201d') outText.Append('"');
            else if (ch is '\n' or '\r' or '\t') outText.Append(' ');
            else outText.Append('?');
        }
        return outText.ToString();
    }
}
