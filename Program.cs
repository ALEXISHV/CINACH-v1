using Microsoft.AspNetCore.RateLimiting;
// API de CINACH: sirve la página (wwwroot) y conecta con SQL Server usando los procedimientos almacenados.
using System.Data;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text.RegularExpressions;
using System.Net;
using System.Net.Mail;
using System.Text;
using System.Globalization;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.Data.SqlClient;

namespace Cinach;
public class Program { public static void Main(string[] args) {
var builder = WebApplication.CreateBuilder(args);
builder.Services.AddAuthentication(CookieAuthenticationDefaults.AuthenticationScheme).AddCookie(o =>
{
    o.Cookie.Name = "cinach_sesion";
    o.Cookie.HttpOnly = true;
    o.Cookie.SameSite = SameSiteMode.Strict;
    o.Cookie.SecurePolicy = CookieSecurePolicy.SameAsRequest;
    o.Events.OnRedirectToAccessDenied = c => { c.Response.StatusCode = 403; return Task.CompletedTask; };
    o.Events.OnValidatePrincipal = async context => {
        var config = context.HttpContext.RequestServices.GetRequiredService<IConfiguration>();
        await using var con = new SqlConnection(config.GetConnectionString("Cinach"));
        await con.OpenAsync();
        await using var cmd = new SqlCommand("SELECT rol FROM usuarios WHERE id_usuario=@id AND activo=1",con);
        cmd.Parameters.AddWithValue("@id",int.Parse(context.Principal!.FindFirstValue(ClaimTypes.NameIdentifier)!));
        var role=await cmd.ExecuteScalarAsync();
        if(role is not string current || current!=context.Principal!.FindFirstValue(ClaimTypes.Role)) {
            context.RejectPrincipal(); await context.HttpContext.SignOutAsync();
        }
    };
    o.ExpireTimeSpan = TimeSpan.FromHours(8);
    o.Events.OnRedirectToLogin = c => { c.Response.StatusCode = 401; return Task.CompletedTask; };
});
builder.Services.AddAuthorization();

builder.Services.AddRateLimiter(o => {
    o.RejectionStatusCode=429;
    o.OnRejected=async (ctx,token)=> { await ctx.HttpContext.Response.WriteAsJsonAsync(new {mensaje="Demasiados intentos. Espera un minuto y vuelve a intentar."},token); };
    o.AddPolicy("login", context =>
    System.Threading.RateLimiting.RateLimitPartition.GetFixedWindowLimiter(
        context.Connection.RemoteIpAddress?.ToString() ?? "unknown", _ => new System.Threading.RateLimiting.FixedWindowRateLimiterOptions {
            PermitLimit=12, Window=TimeSpan.FromMinutes(1), QueueLimit=0 }));
    // Evita que el reenvío voluntario de tickets se convierta en spam.
    o.AddPolicy("ticket-email", context =>
        System.Threading.RateLimiting.RateLimitPartition.GetFixedWindowLimiter(
            context.User.FindFirstValue(ClaimTypes.NameIdentifier) ?? context.Connection.RemoteIpAddress?.ToString() ?? "unknown",
            _ => new System.Threading.RateLimiting.FixedWindowRateLimiterOptions {
                PermitLimit=3, Window=TimeSpan.FromHours(1), QueueLimit=0 }));
});
var app = builder.Build();
var cs = app.Configuration.GetConnectionString("Cinach") ?? throw new InvalidOperationException("Falta ConnectionStrings:Cinach");
app.Use(async (http,next) => {
    try {
        http.Response.Headers["X-Content-Type-Options"]="nosniff";
        http.Response.Headers["Referrer-Policy"]="same-origin";
        if(http.Request.Path.StartsWithSegments("/api")) {
            http.Response.Headers["Cache-Control"]="no-store";
            if(!HttpMethods.IsGet(http.Request.Method) && !HttpMethods.IsHead(http.Request.Method)) {
                if(http.Request.Headers["Sec-Fetch-Site"]=="cross-site") { http.Response.StatusCode=403; return; }
                var origin=http.Request.Headers.Origin.ToString();
                if(origin.Length>0 && (!Uri.TryCreate(origin,UriKind.Absolute,out var u) || u.Authority!=http.Request.Host.Value || u.Scheme!=http.Request.Scheme)) { http.Response.StatusCode=403; return; }
            }
        }
        await next();
    } catch(Exception ex) when (ex is SqlException or FormatException) {
        app.Logger.LogError(ex,"Error procesando solicitud CINACH");
        if(!http.Response.HasStarted) { http.Response.StatusCode=503; await http.Response.WriteAsJsonAsync(new { mensaje="No se pudo completar la solicitud. Revisa la conexión y la actualización de la base de datos." }); }
    }
});
app.UseDefaultFiles();
app.UseStaticFiles();
app.UseAuthentication();
app.UseRateLimiter();
app.UseAuthorization();

var regexCorreo = new Regex(@"^[^\s@]+@[^\s@]+\.[^\s@]+$");
const string Esquema = CookieAuthenticationDefaults.AuthenticationScheme;

static IResult Msg(int codigo, string texto) => Results.Json(new { mensaje = texto }, statusCode: codigo);
static SqlParameter P(string nombre, object? valor) => new(nombre, valor ?? DBNull.Value);
static object Perfil(ClaimsPrincipal p) => new
{
    nombre = p.Identity!.Name,
    correo = p.FindFirstValue(ClaimTypes.Email),
    rol = p.FindFirstValue(ClaimTypes.Role)
};

// PBKDF2: la contraseña llega en texto, se guarda solo su hash (columna usuarios.contrasena).
static string Hashear(string pass)
{
    var salt = RandomNumberGenerator.GetBytes(16);
    var h = Rfc2898DeriveBytes.Pbkdf2(pass, salt, 100_000, HashAlgorithmName.SHA256, 32);
    return $"100000.{Convert.ToBase64String(salt)}.{Convert.ToBase64String(h)}";
}
static bool Verificar(string pass, string guardado)
{
    var p = guardado.Split('.');
    if (p.Length != 3 || !int.TryParse(p[0], out var it)) return false;
    var h = Rfc2898DeriveBytes.Pbkdf2(pass, Convert.FromBase64String(p[1]), it, HashAlgorithmName.SHA256, 32);
    return CryptographicOperations.FixedTimeEquals(h, Convert.FromBase64String(p[2]));
}

// Ejecuta un procedimiento almacenado y devuelve sus filas.
async Task<List<Dictionary<string, object?>>> Sp(string nombre, params SqlParameter[] ps)
{
    var filas = new List<Dictionary<string, object?>>();
    await using var con = new SqlConnection(cs);
    await con.OpenAsync();
    await using var cmd = new SqlCommand(nombre, con) { CommandType = CommandType.StoredProcedure };
    cmd.Parameters.AddRange(ps);
    await using var r = await cmd.ExecuteReaderAsync();
    while (await r.ReadAsync())
    {
        var f = new Dictionary<string, object?>();
        for (var i = 0; i < r.FieldCount; i++) f[r.GetName(i)] = r.IsDBNull(i) ? null : r.GetValue(i);
        filas.Add(f);
    }
    return filas;
}

app.MapGet("/api/peliculas", async (string? genero) =>
{
    try { return Results.Ok(await Sp("dbo.sp_ListarPeliculas", P("@genero", string.IsNullOrWhiteSpace(genero) || genero == "Todas" ? null : genero))); }
    catch (SqlException) { return Msg(500, "No se pudo consultar la cartelera."); }
});

app.MapGet("/api/generos", async () =>
{
    try
    {
        await using var con = new SqlConnection(cs);
        await con.OpenAsync();
        await using var cmd = new SqlCommand("SELECT nombre_categoria FROM categoria_de_peliculas ORDER BY id_categoria", con);
        await using var r = await cmd.ExecuteReaderAsync();
        var lista = new List<string>();
        while (await r.ReadAsync()) lista.Add(r.GetString(0));
        return Results.Ok(lista);
    }
    catch (SqlException) { return Msg(500, "No se pudieron cargar los géneros."); }
});

app.MapPost("/api/auth/registro", async (RegistroDto d) =>
{
    if ((d.Nombre ?? "").Trim().Length < 3 || !regexCorreo.IsMatch((d.Correo ?? "").Trim())
        || (d.Nombre ?? "").Length > 100 || (d.Correo ?? "").Length > 100 || (d.Password ?? "").Length > 128 || (d.Password ?? "").Length < 8 || !Regex.IsMatch(d.Password!, "[A-Za-z]") || !Regex.IsMatch(d.Password!, @"\d"))
        return Msg(400, "Revisa los datos del formulario.");
    try
    {
        // Sin matrícula ni rol por ahora: el rol toma el valor por defecto del procedimiento ('estudiante').
        var correo = d.Correo!.Trim().ToLowerInvariant();
        await Sp("sp_RegistrarUsuario", P("@nombre", d.Nombre!.Trim()), P("@correo", correo), P("@contrasena", Hashear(d.Password!)));
        return Msg(201, "Cuenta creada.");
    }
    catch (SqlException e) when (e.Number is 50000 or 50010) { return Msg(409, e.Message); }
    catch (SqlException) { return Msg(500, "No se pudo crear la cuenta. Inténtalo más tarde."); }
}).RequireRateLimiting("login");

app.MapPost("/api/auth/login", async (LoginDto d, HttpContext http) =>
{
    if (string.IsNullOrWhiteSpace(d.Correo) || string.IsNullOrEmpty(d.Password))
        return Msg(400, "Completa todos los campos.");
    try
    {
        var u = (await Sp("sp_ObtenerUsuarioPorCorreo", P("@correo", d.Correo))).FirstOrDefault();
        if (u is null || !Convert.ToBoolean(u["activo"]) || !Verificar(d.Password, (string)u["contrasena_hash"]!))
            return Msg(401, "Correo o contraseña incorrectos.");
        var claims = new[]
        {
            new Claim(ClaimTypes.NameIdentifier, u["id_usuario"]!.ToString()!),
            new Claim(ClaimTypes.Name, (string)u["nombre"]!),
            new Claim(ClaimTypes.Email, (string)u["correo"]!),
            new Claim(ClaimTypes.Role, (string)u["rol"]!)
        };
        var principal = new ClaimsPrincipal(new ClaimsIdentity(claims, Esquema));
        await http.SignInAsync(Esquema, principal);
        return Results.Ok(new { usuario = Perfil(principal) });
    }
    catch (SqlException) { return Msg(500, "No se pudo iniciar sesión. Inténtalo más tarde."); }
}).RequireRateLimiting("login");

app.MapGet("/api/auth/me", (ClaimsPrincipal p) =>
    Results.Ok(new { usuario = p.Identity?.IsAuthenticated == true ? Perfil(p) : (object?)null }));

app.MapPost("/api/auth/logout", async (HttpContext http) =>
{
    await http.SignOutAsync(Esquema);
    return Results.Ok(new { mensaje = "Sesión cerrada." });
});


// Catálogo de cadenas de cine disponibles.
app.MapGet("/api/cadenas", async () =>
{
    try
    {
        await using var con = new SqlConnection(cs);
        await con.OpenAsync();
        await using var cmd = new SqlCommand("SELECT DISTINCT nombre_cine FROM eleccion_de_cines WHERE activo=1 AND nombre_cine IN (N'Cinépolis',N'Cinemex') ORDER BY nombre_cine", con);
        await using var r = await cmd.ExecuteReaderAsync();
        var datos = new List<string>();
        while (await r.ReadAsync()) datos.Add(r.GetString(0));
        return Results.Ok(datos);
    }
    catch (SqlException) { return Msg(500, "No se pudieron consultar las cadenas de cine."); }
});

// Películas con funciones próximas para una cadena seleccionada.
app.MapGet("/api/cadenas/{marca}/peliculas", async (string marca) =>
{
    if (marca is not ("Cinépolis" or "Cinemex")) return Msg(400, "Selecciona una cadena válida.");
    try
    {
        await using var con = new SqlConnection(cs);
        await con.OpenAsync();
        const string q = @"SELECT DISTINCT p.id_pelicula,p.titulo,p.clasificacion,p.duracion_minutos,p.sinopsis,p.poster_url
          FROM peliculas p INNER JOIN cartelera ca ON ca.id_pelicula=p.id_pelicula
          INNER JOIN numero_de_salas s ON s.id_sala=ca.id_sala
          INNER JOIN eleccion_de_cines c ON c.id_cine=s.id_cine
          INNER JOIN fechas f ON f.id_fecha=ca.id_fecha
          INNER JOIN horarios_de_peliculas h ON h.id_horario=ca.id_horario
          WHERE c.nombre_cine=@marca AND ca.activo=1 AND p.activo=1 AND c.activo=1 AND DATEADD(SECOND,DATEDIFF(SECOND,CAST('00:00' AS time),h.hora_inicio),CAST(f.fecha_proyeccion AS datetime2))>CAST(SYSUTCDATETIME() AT TIME ZONE 'UTC' AT TIME ZONE 'Central America Standard Time' AS datetime2)
          ORDER BY p.titulo";
        await using var cmd = new SqlCommand(q, con); cmd.Parameters.Add(P("@marca", marca));
        await using var r = await cmd.ExecuteReaderAsync();
        var datos = new List<object>();
        while (await r.ReadAsync()) datos.Add(new { id=r.GetInt32(0), titulo=r.GetString(1), clasificacion=r.GetString(2), duracion=r.GetInt32(3), sinopsis=r.IsDBNull(4)?"":r.GetString(4), poster=r.IsDBNull(5)?"":r.GetString(5) });
        return Results.Ok(datos);
    }
    catch (SqlException) { return Msg(500, "No se pudieron consultar las películas."); }
});

// Sucursales de la cadena elegida.
app.MapGet("/api/cines", async (string marca) =>
{
    if (marca is not ("Cinépolis" or "Cinemex")) return Msg(400, "Selecciona una cadena válida.");
    try
    {
        await using var con = new SqlConnection(cs); await con.OpenAsync();
        const string q = @"SELECT id_cine,nombre_cine,COALESCE(nombre_sucursal,N'Sucursal'),direccion,ciudad
                           FROM eleccion_de_cines WHERE activo=1 AND nombre_cine=@marca ORDER BY nombre_sucursal";
        await using var cmd = new SqlCommand(q, con); cmd.Parameters.Add(P("@marca", marca));
        await using var r = await cmd.ExecuteReaderAsync(); var datos = new List<object>();
        while (await r.ReadAsync()) datos.Add(new { id=r.GetInt32(0), marca=r.GetString(1), sucursal=r.GetString(2), direccion=r.GetString(3), ciudad=r.GetString(4) });
        return Results.Ok(datos);
    }
    catch (SqlException) { return Msg(500, "No se pudieron consultar las sucursales."); }
});

// Funciones disponibles para una película en una sucursal.
app.MapGet("/api/funciones", async (int cineId, int peliculaId) =>
{
    try
    {
        await using var con = new SqlConnection(cs); await con.OpenAsync();
        const string q = @"SELECT ca.id_cartelera, f.fecha_proyeccion, h.hora_inicio, s.numero_sala, pb.precio_base
          FROM cartelera ca INNER JOIN fechas f ON f.id_fecha=ca.id_fecha
          INNER JOIN horarios_de_peliculas h ON h.id_horario=ca.id_horario
          INNER JOIN numero_de_salas s ON s.id_sala=ca.id_sala
          INNER JOIN precios_de_boleto pb ON pb.id_precio=ca.id_precio
          INNER JOIN peliculas p ON p.id_pelicula=ca.id_pelicula
          INNER JOIN eleccion_de_cines c ON c.id_cine=s.id_cine
          WHERE s.id_cine=@cine AND ca.id_pelicula=@pelicula AND ca.activo=1 AND p.activo=1 AND c.activo=1 AND DATEADD(SECOND,DATEDIFF(SECOND,CAST('00:00' AS time),h.hora_inicio),CAST(f.fecha_proyeccion AS datetime2))>CAST(SYSUTCDATETIME() AT TIME ZONE 'UTC' AT TIME ZONE 'Central America Standard Time' AS datetime2)
          ORDER BY f.fecha_proyeccion,h.hora_inicio";
        await using var cmd = new SqlCommand(q, con); cmd.Parameters.Add(P("@cine", cineId)); cmd.Parameters.Add(P("@pelicula", peliculaId));
        await using var r = await cmd.ExecuteReaderAsync(); var datos = new List<object>();
        while (await r.ReadAsync()) datos.Add(new { id=r.GetInt32(0), fecha=r.GetDateTime(1).ToString("yyyy-MM-dd"), hora=r.GetTimeSpan(2).ToString(@"hh\:mm"), sala=r.GetString(3), precio=r.GetDecimal(4) });
        return Results.Ok(datos);
    }
    catch (SqlException) { return Msg(500, "No se pudieron consultar los horarios."); }
});

// Plano de asientos. La ocupación se determina por función, no solo por sala.
app.MapGet("/api/funciones/{id:int}/asientos", async (int id) =>
{
    try
    {
        await using var con = new SqlConnection(cs); await con.OpenAsync();
        const string q = @"SELECT a.id_asiento,a.fila,a.numero_asiento,
          CAST(CASE WHEN d.id_asiento IS NULL THEN 0 ELSE 1 END AS bit) ocupado
          FROM cartelera ca INNER JOIN numero_de_asientos a ON a.id_sala=ca.id_sala
          LEFT JOIN detalle_ticket_asientos d ON d.id_asiento=a.id_asiento AND d.id_cartelera=ca.id_cartelera AND d.activo=1
          WHERE ca.id_cartelera=@id AND ca.activo=1 ORDER BY a.fila,a.numero_asiento";
        await using var cmd = new SqlCommand(q, con); cmd.Parameters.Add(P("@id", id));
        await using var r = await cmd.ExecuteReaderAsync(); var datos = new List<object>();
        while (await r.ReadAsync()) datos.Add(new { id=r.GetInt32(0), fila=r.GetString(1), numero=r.GetString(2), ocupado=r.GetBoolean(3) });
        return Results.Ok(datos);
    }
    catch (SqlException) { return Msg(500, "No se pudieron consultar los asientos."); }
});

// Compra académica: solo admite la tarjeta de prueba publicada en la interfaz.
app.MapPost("/api/compras", async (CompraDto d, ClaimsPrincipal usuario) =>
{
    if (usuario.Identity?.IsAuthenticated != true) return Msg(401, "Inicia sesión para comprar boletos.");
    if (d.IdCartelera <= 0 || d.Asientos is null || d.Asientos.Length is < 1 or > 8 ||
        string.IsNullOrWhiteSpace(d.Titular) || d.Titular.Trim().Length is < 3 or > 100 ||
        Regex.Replace(d.TarjetaPrueba ?? "", @"\s", "") != "4242424242424242")
        return Msg(400, "Completa los datos y utiliza únicamente la tarjeta de prueba indicada.");
    var usuarioIdTexto = usuario.FindFirstValue(ClaimTypes.NameIdentifier);
    if (!int.TryParse(usuarioIdTexto, out var usuarioId)) return Msg(401, "La sesión no es válida.");
    var correo = usuario.FindFirstValue(ClaimTypes.Email) ?? "";
    var asientos = d.Asientos.Distinct().ToArray();
    if (asientos.Length != d.Asientos.Length || asientos.Any(x => x <= 0)) return Msg(400, "La selección de asientos no es válida.");
    try
    {
        await using var con = new SqlConnection(cs); await con.OpenAsync();
        int formaPago;
        await using (var cmdPago = new SqlCommand("SELECT TOP 1 id_forma_pago FROM forma_de_pago WHERE metodo=N'Tarjeta de Crédito' ORDER BY id_forma_pago", con))
        { var v = await cmdPago.ExecuteScalarAsync(); if (v is null) return Msg(500, "No está configurado el método de pago de prueba."); formaPago = Convert.ToInt32(v); }
        await using var cmd = new SqlCommand("dbo.sp_ProcesarCompraConTarjeta", con) { CommandType = CommandType.StoredProcedure };
        cmd.Parameters.Add(P("@id_usuario", usuarioId)); cmd.Parameters.Add(P("@correo_contacto", correo));
        cmd.Parameters.Add(P("@id_cartelera", d.IdCartelera)); cmd.Parameters.Add(P("@id_forma_pago", formaPago));
        // Nunca se recibe ni almacena una tarjeta bancaria real. Se envía un número fijo de prueba al SP.
        cmd.Parameters.Add(P("@numero_tarjeta", "4242424242424242")); cmd.Parameters.Add(P("@titular_tarjeta", d.Titular.Trim()));
        cmd.Parameters.Add(P("@lista_asientos", string.Join(",", asientos))); cmd.Parameters.Add(P("@id_promocion", DBNull.Value));
        await using var r = await cmd.ExecuteReaderAsync();
        if (!await r.ReadAsync()) return Msg(500, "No se pudo generar el ticket.");
        var folio = r["FolioGenerado"]?.ToString() ?? "";
        var total = Convert.ToDecimal(r["TotalPagado"]);
        var ticket = await ObtenerTicket(folio, usuarioId);
        var enviado = false;
        if (ticket is not null) enviado = await EnviarTicketCorreo(ticket, correo, app.Configuration);
        return Results.Ok(new { folio, total, correo, correoEnviado=enviado, ticket, mensaje="Compra registrada." });
    }
    catch (SqlException e) when (e.Number is >= 50020 and <= 50030) { return Msg(409, e.Message); }
    catch (SqlException) { return Msg(500, "No se pudo completar la compra. Actualiza los asientos e inténtalo nuevamente."); }
});

// Recupera el ticket únicamente para el usuario propietario.
app.MapGet("/api/tickets/{folio}", async (string folio, ClaimsPrincipal usuario) =>
{
    if (usuario.Identity?.IsAuthenticated != true) return Msg(401, "Inicia sesión para consultar tu ticket.");
    if (!int.TryParse(usuario.FindFirstValue(ClaimTypes.NameIdentifier), out var uid)) return Msg(401, "Sesión no válida.");
    try
    {
        var t = await ObtenerTicket(folio, uid);
        return t is null ? Msg(404, "No se encontró el ticket.") : Results.Ok(t);
    }
    catch (SqlException) { return Msg(500, "No se pudo consultar el ticket."); }
});

// Descarga directa de PDF: sólo el usuario que compró el ticket puede obtenerlo.
app.MapGet("/api/tickets/{folio}/pdf", async (string folio, ClaimsPrincipal usuario) =>
{
    if (usuario.Identity?.IsAuthenticated != true) return Msg(401, "Inicia sesión para descargar tu ticket.");
    if (!int.TryParse(usuario.FindFirstValue(ClaimTypes.NameIdentifier), out var uid)) return Msg(401, "Sesión no válida.");
    try
    {
        var ticket = await ObtenerTicket(folio, uid);
        if (ticket is null) return Msg(404, "No se encontró el ticket.");
        var limpio = Regex.Replace(folio, @"[^a-zA-Z0-9-]", "");
        if (string.IsNullOrEmpty(limpio)) limpio = "boleto";
        return Results.File(TicketPdf.Create(ticket), "application/pdf", $"CINACH-{limpio}.pdf");
    }
    catch (SqlException) { return Msg(500, "No se pudo obtener el ticket."); }
}).RequireAuthorization();

// Si el correo no se pudo entregar al comprar, permite reintentar sin generar otra compra.
app.MapPost("/api/tickets/{folio}/reenviar", async (string folio, ClaimsPrincipal usuario) =>
{
    if (!int.TryParse(usuario.FindFirstValue(ClaimTypes.NameIdentifier), out var uid)) return Msg(401, "Sesión no válida.");
    try
    {
        var ticket = await ObtenerTicket(folio, uid);
        if (ticket is null) return Msg(404, "No se encontró el ticket.");
        var correo = usuario.FindFirstValue(ClaimTypes.Email) ?? "";
        if (string.IsNullOrWhiteSpace(correo)) return Msg(400, "Tu cuenta no tiene correo registrado.");
        if (!await EnviarTicketCorreo(ticket, correo, app.Configuration))
            return Msg(503, "No se pudo enviar el correo. Verifica la configuración de Gmail o inténtalo después.");
        return Results.Ok(new { mensaje = $"Ticket enviado a {correo}.", correoEnviado = true });
    }
    catch (SqlException) { return Msg(500, "No se pudo consultar el ticket."); }
}).RequireAuthorization().RequireRateLimiting("ticket-email");

async Task<Dictionary<string, object?>?> ObtenerTicket(string folio, int uid)
{
    await using var con = new SqlConnection(cs); await con.OpenAsync();
    const string q = @"SELECT TOP 1 t.folio_alfanumerico folio,t.correo_contacto correo,t.fecha_emision fecha,
      t.total_pagado total,p.titulo pelicula,c.nombre_cine cine,COALESCE(c.nombre_sucursal,N'Sucursal') sucursal,
      c.direccion direccion,c.ciudad ciudad,s.numero_sala sala,f.fecha_proyeccion fechaFuncion,
      h.hora_inicio hora,STRING_AGG(CONCAT(a.fila,a.numero_asiento),N', ') asientos,
      tt.codigo_autorizacion autorizacion,tt.numero_tarjeta_enmascarado tarjeta,tt.estado_pago estado
      FROM generador_de_ticket t INNER JOIN cartelera ca ON ca.id_cartelera=t.id_cartelera
      INNER JOIN peliculas p ON p.id_pelicula=ca.id_pelicula INNER JOIN numero_de_salas s ON s.id_sala=ca.id_sala
      INNER JOIN eleccion_de_cines c ON c.id_cine=s.id_cine INNER JOIN fechas f ON f.id_fecha=ca.id_fecha
      INNER JOIN horarios_de_peliculas h ON h.id_horario=ca.id_horario
      INNER JOIN detalle_ticket_asientos d ON d.id_ticket=t.id_ticket INNER JOIN numero_de_asientos a ON a.id_asiento=d.id_asiento
      LEFT JOIN transacciones_tarjeta tt ON tt.id_ticket=t.id_ticket
      WHERE t.folio_alfanumerico=@folio AND t.id_usuario=@uid
      GROUP BY t.folio_alfanumerico,t.correo_contacto,t.fecha_emision,t.total_pagado,p.titulo,c.nombre_cine,c.nombre_sucursal,c.direccion,c.ciudad,s.numero_sala,f.fecha_proyeccion,h.hora_inicio,tt.codigo_autorizacion,tt.numero_tarjeta_enmascarado,tt.estado_pago";
    await using var cmd = new SqlCommand(q, con); cmd.Parameters.Add(P("@folio", folio)); cmd.Parameters.Add(P("@uid", uid));
    await using var r = await cmd.ExecuteReaderAsync(); if (!await r.ReadAsync()) return null;
    var d = new Dictionary<string, object?>(); for (int i=0;i<r.FieldCount;i++) d[r.GetName(i)] = r.IsDBNull(i)?null:r.GetValue(i);
    return d;
}

async Task<bool> EnviarTicketCorreo(Dictionary<string, object?> ticket, string destino, IConfiguration cfg)
{
    var host=cfg["Email:Host"]; var from=cfg["Email:From"]; var user=cfg["Email:User"]; var pass=cfg["Email:Password"];
    if (string.IsNullOrWhiteSpace(host) || string.IsNullOrWhiteSpace(from) ||
        string.IsNullOrWhiteSpace(user) || string.IsNullOrWhiteSpace(pass) ||
        string.IsNullOrWhiteSpace(destino)) return false;
    try
    {
        using var msg = new MailMessage(); msg.From = new MailAddress(from, cfg["Email:FromName"] ?? "CINACH");
        msg.To.Add(destino); msg.Subject = $"Tu ticket CINACH - {ticket["folio"]}"; msg.IsBodyHtml = true;
        string V(string k) => WebUtility.HtmlEncode(Convert.ToString(ticket.GetValueOrDefault(k)) ?? "");
        msg.Body = $@"<div style='font-family:Arial,sans-serif;max-width:600px;margin:auto;padding:24px;border:1px solid #ddd;border-radius:12px'>
          <h1 style='color:#bd8b2c'>CINACH</h1><h2>Tu compra CINACH</h2>
          <p><b>Folio:</b> {V("folio")}</p><p><b>Película:</b> {V("pelicula")}</p><p><b>Cine:</b> {V("cine")} - {V("sucursal")}</p>
          <p><b>Fecha:</b> {V("fechaFuncion")} <b>Hora:</b> {V("hora")}</p><p><b>Sala:</b> {V("sala")}</p>
          <p><b>Asientos:</b> {V("asientos")}</p><p><b>Total:</b> ${V("total")}</p>
          <p><b>Referencia:</b> {V("autorizacion")}</p><p>Adjuntamos tu comprobante PDF.</p>
          <hr><p>CINACH académico. Sin cargos bancarios; no válido para acceso a salas comerciales.</p></div>";
        var folio = Regex.Replace(Convert.ToString(ticket.GetValueOrDefault("folio")) ?? "", @"[^a-zA-Z0-9-]", "");
        if (string.IsNullOrEmpty(folio)) folio = "boleto";
        msg.Attachments.Add(new Attachment(new MemoryStream(TicketPdf.Create(ticket)), $"CINACH-{folio}.pdf", "application/pdf"));
        using var smtp = new SmtpClient(host, int.TryParse(cfg["Email:Port"],out var port)?port:587)
        {
            EnableSsl=bool.TryParse(cfg["Email:EnableSsl"],out var ssl)?ssl:true,
            DeliveryMethod=SmtpDeliveryMethod.Network,
            UseDefaultCredentials=false,
            Credentials=new NetworkCredential(user, pass),
            Timeout=20000
        };
        using var limite = new CancellationTokenSource(TimeSpan.FromSeconds(20));
        await smtp.SendMailAsync(msg, limite.Token); return true;
    }
    catch (Exception ex)
    {
        // Un problema SMTP o PDF nunca debe invalidar una compra ya guardada.
        // No se registran credenciales ni datos de la cuenta en los logs.
        app.Logger.LogWarning("No se envió un ticket por SMTP (tipo de error: {Tipo}).", ex.GetType().Name);
        return false;
    }
}


AdminApi.Map(app, cs);
app.Run();
}}
record RegistroDto(string? Nombre, string? Correo, string? Password);
record LoginDto(string? Correo, string? Password);
record CompraDto(int IdCartelera, int[]? Asientos, string? Titular, string? TarjetaPrueba);

