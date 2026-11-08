using System.Data;
using System.Globalization;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text.RegularExpressions;
using Microsoft.Data.SqlClient;

static class AdminApi
{
    static SqlParameter P(string n, object? v) => new(n,v??DBNull.Value);
    static IResult Error(int code,string msg)=>Results.Json(new{mensaje=msg},statusCode:code);
    const string Now = "CAST(SYSUTCDATETIME() AT TIME ZONE 'UTC' AT TIME ZONE 'Central America Standard Time' AS datetime2)";
    static async Task<List<Dictionary<string,object?>>> Query(string cs,string sql,params SqlParameter[] ps) {
        await using var con=new SqlConnection(cs); await con.OpenAsync();
        await using var cmd=new SqlCommand(sql,con); cmd.Parameters.AddRange(ps);
        await using var r=await cmd.ExecuteReaderAsync(); var rows=new List<Dictionary<string,object?>>();
        while(await r.ReadAsync()) { var d=new Dictionary<string,object?>(); for(int i=0;i<r.FieldCount;i++) d[r.GetName(i)]=r.IsDBNull(i)?null:r.GetValue(i); rows.Add(d); } return rows;
    }
    // A single transaction lock coordinates purchases, schedule changes and catalog edits.
    static async Task<IResult> Write(string cs,Func<SqlConnection,SqlTransaction,Task<IResult>> operation) {
        await using var con=new SqlConnection(cs); await con.OpenAsync();
        await using var tx=(SqlTransaction)await con.BeginTransactionAsync();
        try {
            await using var l=new SqlCommand("DECLARE @r int; EXEC @r=sys.sp_getapplock @Resource=N'CINACH_OPERACIONES',@LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=10000; IF @r<0 THROW 50029,'Intenta nuevamente.',1;",con,tx); await l.ExecuteNonQueryAsync();
            var result=await operation(con,tx); await tx.CommitAsync(); return result;
        } catch(SqlException e) { await tx.RollbackAsync(); return Error(409,e.Number is 2601 or 2627?"Ya existe un registro con esos datos.":"No se pudo guardar. Verifica los datos y sus relaciones."); }
    }
    static async Task<object?> Scalar(SqlConnection c,SqlTransaction t,string sql,params SqlParameter[] ps) {
        await using var cmd=new SqlCommand(sql,c,t);cmd.Parameters.AddRange(ps);return await cmd.ExecuteScalarAsync();
    }
    static Task<object?> Run(SqlConnection c,SqlTransaction t,string sql,params SqlParameter[] ps)=>Scalar(c,t,sql,ps);
    static string Hash(string pass) { var salt=RandomNumberGenerator.GetBytes(16);return $"100000.{Convert.ToBase64String(salt)}.{Convert.ToBase64String(Rfc2898DeriveBytes.Pbkdf2(pass,salt,100000,HashAlgorithmName.SHA256,32))}"; }
    public static void Map(WebApplication app,string cs) {
        var g=app.MapGroup("/api/admin").RequireAuthorization(p=>p.RequireRole("admin"));
        g.MapGet("/catalogos",async()=>Results.Ok(new {
            categorias=await Query(cs,"SELECT id_categoria id,nombre_categoria nombre FROM categoria_de_peliculas ORDER BY nombre_categoria"),
            peliculas=await Query(cs,"SELECT id_pelicula id,titulo nombre FROM peliculas WHERE activo=1 ORDER BY titulo"),
            salas=await Query(cs,"SELECT s.id_sala id,CONCAT(c.nombre_cine,' · ',c.nombre_sucursal,' · ',s.numero_sala) nombre FROM numero_de_salas s JOIN eleccion_de_cines c ON c.id_cine=s.id_cine WHERE c.activo=1 ORDER BY nombre"),
            precios=await Query(cs,"SELECT id_precio id,CONCAT(tipo_boleto,' · $',precio_base) nombre FROM precios_de_boleto ORDER BY precio_base")
        }));
        g.MapGet("/peliculas",async()=>Results.Ok(await Query(cs,"SELECT id_pelicula id,titulo,sinopsis,duracion_minutos duracion,clasificacion,poster_url poster,id_categoria categoria,activo FROM peliculas ORDER BY id_pelicula DESC")));
        g.MapPost("/peliculas",(Movie d)=>SaveMovie(cs,0,d));
        g.MapPut("/peliculas/{id:int}",(int id,Movie d)=>SaveMovie(cs,id,d));
        g.MapDelete("/peliculas/{id:int}",(int id)=>Write(cs,async(c,t)=> {
            var n=await Scalar(c,t,"UPDATE peliculas SET activo=0 WHERE id_pelicula=@id; SELECT @@ROWCOUNT",P("@id",id));
            return Convert.ToInt32(n)==0?Error(404,"Película no encontrada."):Results.Ok(new{mensaje="Película dada de baja. Se conserva el historial."});
        }));
        g.MapGet("/usuarios",async()=>Results.Ok(await Query(cs,"SELECT id_usuario id,nombre,correo,rol,activo,fecha_registro fecha FROM usuarios ORDER BY id_usuario DESC")));
        g.MapPost("/usuarios",(User d,ClaimsPrincipal u)=>SaveUser(cs,0,d,u));
        g.MapPut("/usuarios/{id:int}",(int id,User d,ClaimsPrincipal u)=>SaveUser(cs,id,d,u));
        g.MapDelete("/usuarios/{id:int}",(int id,ClaimsPrincipal u)=>Write(cs,async(c,t)=> {
            if(u.FindFirstValue(ClaimTypes.NameIdentifier)==id.ToString()) return Error(400,"No puedes desactivar tu propia cuenta.");
            var role=await Scalar(c,t,"SELECT rol FROM usuarios WHERE id_usuario=@id",P("@id",id));
            if(role is null)return Error(404,"Usuario no encontrado.");
            if((string)role=="admin" && Convert.ToInt32(await Scalar(c,t,"SELECT COUNT(*) FROM usuarios WHERE rol='admin' AND activo=1 AND id_usuario<>@id",P("@id",id)))==0) return Error(400,"Debe existir al menos un administrador activo.");
            await Run(c,t,"UPDATE usuarios SET activo=0 WHERE id_usuario=@id",P("@id",id));return Results.Ok(new{mensaje="Usuario desactivado."});
        }));
        // El estado se calcula con la hora local de Tuxtla en SQL Server.
        // No hace falta un proceso nocturno, ni eliminar funciones históricas.
        g.MapGet("/funciones",async()=>Results.Ok(await Query(cs,@"SELECT ca.id_cartelera id,ca.id_pelicula peliculaId,ca.id_sala salaId,ca.id_precio precioId,ca.activo,
          p.titulo pelicula,CONCAT(c.nombre_cine,' · ',c.nombre_sucursal) sucursal,s.numero_sala sala,
          CONVERT(varchar(10),f.fecha_proyeccion,23) fecha,CONVERT(varchar(5),h.hora_inicio,108) hora,CONVERT(varchar(5),h.hora_fin,108) horaFin,
          pb.precio_base precio,(SELECT COUNT(*) FROM detalle_ticket_asientos d WHERE d.id_cartelera=ca.id_cartelera AND d.activo=1) boletosVendidos,
          (SELECT COUNT(*) FROM generador_de_ticket t WHERE t.id_cartelera=ca.id_cartelera) ticketsEmitidos,
          CASE WHEN ca.activo=0 THEN N'Inactiva'
               WHEN tiempos.fin<=reloj.ahora THEN N'Finalizada'
               WHEN tiempos.inicio<=reloj.ahora THEN N'En curso'
               ELSE N'Próxima' END estado
          FROM cartelera ca JOIN peliculas p ON p.id_pelicula=ca.id_pelicula JOIN numero_de_salas s ON s.id_sala=ca.id_sala JOIN eleccion_de_cines c ON c.id_cine=s.id_cine
          JOIN fechas f ON f.id_fecha=ca.id_fecha JOIN horarios_de_peliculas h ON h.id_horario=ca.id_horario JOIN precios_de_boleto pb ON pb.id_precio=ca.id_precio
          CROSS APPLY (SELECT
            DATEADD(second,DATEDIFF(second,CAST('00:00' AS time),h.hora_inicio),CAST(f.fecha_proyeccion AS datetime2)) inicio,
            DATEADD(second,DATEDIFF(second,CAST('00:00' AS time),h.hora_fin),CAST(f.fecha_proyeccion AS datetime2)) fin
          ) tiempos
          CROSS JOIN (SELECT CAST(SYSUTCDATETIME() AT TIME ZONE 'UTC' AT TIME ZONE 'Central America Standard Time' AS datetime2) ahora) reloj
          ORDER BY f.fecha_proyeccion DESC,h.hora_inicio DESC")));
        g.MapPost("/funciones",(Show d)=>SaveShow(cs,0,d));
        g.MapPut("/funciones/{id:int}",(int id,Show d)=>SaveShow(cs,id,d));
        g.MapDelete("/funciones/{id:int}",(int id)=>Write(cs,async(c,t)=> {
            if(Convert.ToInt32(await Scalar(c,t,"SELECT COUNT(*) FROM generador_de_ticket WHERE id_cartelera=@id",P("@id",id)))>0)return Error(409,"No puedes dar de baja una función con tickets emitidos.");
            var n=await Scalar(c,t,"UPDATE cartelera SET activo=0 WHERE id_cartelera=@id; SELECT @@ROWCOUNT",P("@id",id));
            return Convert.ToInt32(n)==0?Error(404,"Función no encontrada."):Results.Ok(new{mensaje="Función dada de baja."});
        }));
        g.MapGet("/estadisticas",async(string? desde,string? hasta)=> {
            if(!DateOnly.TryParseExact(desde,"yyyy-MM-dd",out var start)||!DateOnly.TryParseExact(hasta,"yyyy-MM-dd",out var end)||end<start||end.DayNumber-start.DayNumber>366) return Error(400,"Selecciona un rango de hasta 366 días.");
            // Count seats per purchase BEFORE summing money, so totals are never multiplied.
            var rows=await Query(cs,@"SELECT p.titulo pelicula,COUNT(*) compras,SUM(a.boletos) boletos,SUM(t.total_pagado) ingresos
                FROM generador_de_ticket t JOIN cartelera c ON c.id_cartelera=t.id_cartelera JOIN peliculas p ON p.id_pelicula=c.id_pelicula
                CROSS APPLY(SELECT COUNT(*) boletos FROM detalle_ticket_asientos d WHERE d.id_ticket=t.id_ticket AND d.activo=1)a
                WHERE CONVERT(date,t.fecha_emision)>=@desde AND CONVERT(date,t.fecha_emision)<=@hasta
                AND EXISTS(SELECT 1 FROM transacciones_tarjeta tt WHERE tt.id_ticket=t.id_ticket AND tt.estado_pago=N'APROBADO')
                GROUP BY p.id_pelicula,p.titulo ORDER BY ingresos DESC",P("@desde",start.ToDateTime(TimeOnly.MinValue)),P("@hasta",end.ToDateTime(TimeOnly.MinValue)));
            return Results.Ok(new{peliculas=rows,compras=rows.Sum(x=>Convert.ToInt32(x["compras"])),boletos=rows.Sum(x=>Convert.ToInt32(x["boletos"])),ingresos=rows.Sum(x=>Convert.ToDecimal(x["ingresos"]))});
        });
        app.MapGet("/api/mis-compras",async(ClaimsPrincipal u)=>Results.Ok(await Query(cs,@"SELECT t.folio_alfanumerico folio,t.fecha_emision fecha,t.total_pagado total,p.titulo pelicula,
            COALESCE((SELECT TOP 1 estado_pago FROM transacciones_tarjeta tt WHERE tt.id_ticket=t.id_ticket ORDER BY id_transaccion DESC),'APROBADO') estado
            FROM generador_de_ticket t JOIN cartelera c ON c.id_cartelera=t.id_cartelera JOIN peliculas p ON p.id_pelicula=c.id_pelicula
            WHERE t.id_usuario=@uid ORDER BY t.fecha_emision DESC",P("@uid",int.Parse(u.FindFirstValue(ClaimTypes.NameIdentifier)!))))).RequireAuthorization();
    }
    static Task<IResult> SaveMovie(string cs,int id,Movie d) {
        if(string.IsNullOrWhiteSpace(d.Titulo)||d.Titulo.Trim().Length>100||d.Duracion is < 1 or > 600||d.Categoria<1||!new[]{"AA","A","B","B15","C","D"}.Contains(d.Clasificacion)|| (d.Sinopsis?.Length??0)>5000 || (d.Poster?.Length??0)>200 || (!string.IsNullOrEmpty(d.Poster)&&!Regex.IsMatch(d.Poster,@"^img/posters/[A-Za-z0-9_-]+\.(jpg|jpeg|png|webp)$"))) return Task.FromResult(Error(400,"Revisa título, duración, categoría y clasificación. El póster debe ser una ruta local img/posters/archivo.jpg (png o webp también)."));
        return Write(cs,async(c,t)=> {
            if(id>0 && Convert.ToInt32(await Scalar(c,t,"SELECT COUNT(*) FROM peliculas WHERE id_pelicula=@id",P("@id",id)))==0)return Error(404,"Película no encontrada.");
            if(id>0 && Convert.ToInt32(await Scalar(c,t,"SELECT COUNT(*) FROM cartelera ca JOIN peliculas p ON p.id_pelicula=ca.id_pelicula WHERE p.id_pelicula=@id AND ca.activo=1 AND p.duracion_minutos<>@min",P("@id",id),P("@min",d.Duracion)))>0)return Error(409,"Da de baja las funciones activas antes de cambiar la duración.");
            await Run(c,t,id==0?"INSERT peliculas(titulo,sinopsis,duracion_minutos,clasificacion,poster_url,id_categoria,activo) VALUES(@titulo,@sinopsis,@min,@clas,@poster,@cat,@activo)":"UPDATE peliculas SET titulo=@titulo,sinopsis=@sinopsis,duracion_minutos=@min,clasificacion=@clas,poster_url=@poster,id_categoria=@cat,activo=@activo WHERE id_pelicula=@id",P("@id",id),P("@titulo",d.Titulo.Trim()),P("@sinopsis",d.Sinopsis),P("@min",d.Duracion),P("@clas",d.Clasificacion),P("@poster",d.Poster),P("@cat",d.Categoria),P("@activo",d.Activo));
            return Results.Ok(new{mensaje="Película guardada."});
        });
    }
    static Task<IResult> SaveUser(string cs,int id,User d,ClaimsPrincipal current) {
        if(string.IsNullOrWhiteSpace(d.Nombre)||d.Nombre.Trim().Length is <3 or >100 || (d.Correo?.Length??0)>100 || !Regex.IsMatch(d.Correo??"",@"^[^\s@]+@[^\s@]+\.[^\s@]+$") || !new[]{"estudiante","docente","admin"}.Contains(d.Rol) || (id==0 && (d.Password is null || d.Password.Length is <8 or >128 || !Regex.IsMatch(d.Password,"[A-Za-z]") || !Regex.IsMatch(d.Password,@"\d")))) return Task.FromResult(Error(400,"Revisa nombre, correo, rol y contraseña (8–128 caracteres, letras y números)."));
        return Write(cs,async(c,t)=> {
            if(id>0) {
                if(current.FindFirstValue(ClaimTypes.NameIdentifier)==id.ToString() && (!d.Activo || d.Rol!="admin"))return Error(400,"No puedes quitarte el acceso administrativo.");
                var role=await Scalar(c,t,"SELECT rol FROM usuarios WHERE id_usuario=@id",P("@id",id));if(role is null)return Error(404,"Usuario no encontrado.");
                if((string)role=="admin"&&(!d.Activo||d.Rol!="admin")&&Convert.ToInt32(await Scalar(c,t,"SELECT COUNT(*) FROM usuarios WHERE rol='admin' AND activo=1 AND id_usuario<>@id",P("@id",id)))==0)return Error(400,"Debe quedar al menos un administrador activo.");
            }
            await Run(c,t,id==0?"INSERT usuarios(nombre,correo,rol,activo,contrasena) VALUES(@nombre,@correo,@rol,@activo,@hash)":"UPDATE usuarios SET nombre=@nombre,correo=@correo,rol=@rol,activo=@activo WHERE id_usuario=@id",P("@id",id),P("@nombre",d.Nombre!.Trim()),P("@correo",d.Correo!.Trim().ToLowerInvariant()),P("@rol",d.Rol),P("@activo",d.Activo),P("@hash",id==0?Hash(d.Password!):""));
            return Results.Ok(new{mensaje="Usuario guardado."});
        });
    }
    static Task<IResult> SaveShow(string cs,int id,Show d) {
        if(!DateOnly.TryParseExact(d.Fecha,"yyyy-MM-dd",out var date)||!TimeOnly.TryParseExact(d.HoraInicio,"HH:mm",out var time)||d.PeliculaId<1||d.SalaId<1||d.PrecioId<1)return Task.FromResult(Error(400,"Completa película, sala, precio, fecha y hora."));
        var begin=date.ToDateTime(time);
        return Write(cs,async(c,t)=> {
            if(id>0 && Convert.ToInt32(await Scalar(c,t,"SELECT COUNT(*) FROM cartelera WHERE id_cartelera=@id",P("@id",id)))==0)return Error(404,"Función no encontrada.");
            // Nunca cambiar la fecha o sala de una función que ya comenzó: preserva el historial.
            // Para volver a ofrecer la película se registra una nueva función, con otro id_cartelera.
            if(id>0 && Convert.ToInt32(await Scalar(c,t,@"SELECT COUNT(*) FROM cartelera ca
                JOIN fechas f ON f.id_fecha=ca.id_fecha
                JOIN horarios_de_peliculas h ON h.id_horario=ca.id_horario
                WHERE ca.id_cartelera=@id AND DATEADD(second,DATEDIFF(second,CAST('00:00' AS time),h.hora_inicio),CAST(f.fecha_proyeccion AS datetime2))<="+Now,P("@id",id)))>0)
                return Error(409,"Esta función ya comenzó o terminó. Usa Reprogramar para crear una nueva función sin afectar el historial.");
            if(id>0 && Convert.ToInt32(await Scalar(c,t,"SELECT COUNT(*) FROM generador_de_ticket WHERE id_cartelera=@id",P("@id",id)))>0)return Error(409,"La función tiene tickets emitidos; no puede modificarse. Usa Reprogramar para crear otra función.");
            var now=Convert.ToDateTime(await Scalar(c,t,"SELECT "+Now));if(begin<=now)return Error(400,"La función debe comenzar en el futuro (hora de Tuxtla).");
            var mins=await Scalar(c,t,"SELECT duracion_minutos FROM peliculas WHERE id_pelicula=@p AND activo=1",P("@p",d.PeliculaId));if(mins is null)return Error(400,"Selecciona una película activa.");
            var finish=begin.AddMinutes(Convert.ToInt32(mins));if(finish.Date!=begin.Date)return Error(400,"Programa una función que termine antes de medianoche.");
            if(Convert.ToInt32(await Scalar(c,t,"SELECT COUNT(*) FROM numero_de_salas s JOIN eleccion_de_cines c ON c.id_cine=s.id_cine WHERE s.id_sala=@s AND c.activo=1",P("@s",d.SalaId)))==0)return Error(400,"Sala no disponible.");
            var conflicts=await Scalar(c,t,@"SELECT COUNT(*) FROM cartelera ca JOIN fechas f ON f.id_fecha=ca.id_fecha JOIN horarios_de_peliculas h ON h.id_horario=ca.id_horario
              WHERE ca.activo=1 AND ca.id_cartelera<>@id AND ca.id_sala=@s AND f.fecha_proyeccion=@fecha
              AND @inicio<DATEADD(minute,20,DATEADD(second,DATEDIFF(second,CAST('00:00' AS time),h.hora_fin),CAST(f.fecha_proyeccion AS datetime2)))
              AND @fin>DATEADD(second,DATEDIFF(second,CAST('00:00' AS time),h.hora_inicio),CAST(f.fecha_proyeccion AS datetime2))",P("@id",id),P("@s",d.SalaId),P("@fecha",begin.Date),P("@inicio",begin),P("@fin",finish.AddMinutes(20)));
            if(d.Activo&&Convert.ToInt32(conflicts)>0)return Error(409,"El horario se cruza con otra función. Deja 20 minutos para limpieza.");
            var fid=await Scalar(c,t,"SELECT id_fecha FROM fechas WHERE fecha_proyeccion=@f",P("@f",begin.Date));
            if(fid is null)fid=await Scalar(c,t,"INSERT fechas(fecha_proyeccion,dia_semana) VALUES(@f,@dia); SELECT CAST(SCOPE_IDENTITY() AS int)",P("@f",begin.Date),P("@dia",begin.ToString("dddd",new CultureInfo("es-MX"))));
            var hid=await Scalar(c,t,"SELECT TOP 1 id_horario FROM horarios_de_peliculas WHERE hora_inicio=@a AND hora_fin=@b",P("@a",begin.TimeOfDay),P("@b",finish.TimeOfDay));
            if(hid is null)hid=await Scalar(c,t,"INSERT horarios_de_peliculas(hora_inicio,hora_fin) VALUES(@a,@b); SELECT CAST(SCOPE_IDENTITY() AS int)",P("@a",begin.TimeOfDay),P("@b",finish.TimeOfDay));
            await Run(c,t,id==0?"INSERT cartelera(id_pelicula,id_sala,id_precio,id_fecha,id_horario,activo) VALUES(@p,@s,@pr,@f,@h,@activo)":"UPDATE cartelera SET id_pelicula=@p,id_sala=@s,id_precio=@pr,id_fecha=@f,id_horario=@h,activo=@activo WHERE id_cartelera=@id",P("@id",id),P("@p",d.PeliculaId),P("@s",d.SalaId),P("@pr",d.PrecioId),P("@f",fid),P("@h",hid),P("@activo",d.Activo));
            return Results.Ok(new{mensaje="Función guardada."});
        });
    }
    record Movie(string? Titulo,string? Sinopsis,int Duracion,string Clasificacion,string? Poster,int Categoria,bool Activo);
    record User(string? Nombre,string? Correo,string Rol,bool Activo,string? Password);
    record Show(int PeliculaId,int SalaId,int PrecioId,string Fecha,string HoraInicio,bool Activo);
}
