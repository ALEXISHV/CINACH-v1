-- Programacion interna de CINACH: NO representa cartelera, precios o planos oficiales.
-- Reejecutable: agrega los proximos siete dias, sin borrar compras ni alterar funciones existentes.
SET NOCOUNT ON;
SET XACT_ABORT ON;
BEGIN TRANSACTION;
DECLARE @lock INT;
EXEC @lock=sys.sp_getapplock @Resource=N'CINACH_OPERACIONES',@LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=10000;
IF @lock<0 BEGIN ROLLBACK; THROW 51000,'No se pudo obtener el bloqueo.',1; END;
INSERT numero_de_salas(numero_sala,capacidad_asientos,id_cine)
SELECT v.nombre,40,c.id_cine FROM eleccion_de_cines c CROSS JOIN(VALUES(N'Sala 1'),(N'Sala 2'))v(nombre)
WHERE c.activo=1 AND c.ciudad=N'Tuxtla Gutiérrez' AND NOT EXISTS(SELECT 1 FROM numero_de_salas s WHERE s.id_cine=c.id_cine AND s.numero_sala=v.nombre);
INSERT numero_de_asientos(numero_asiento,fila,id_sala)
SELECT CONVERT(nvarchar(5),n.num),f.fila,s.id_sala FROM numero_de_salas s JOIN eleccion_de_cines c ON c.id_cine=s.id_cine
CROSS JOIN(VALUES(N'A'),(N'B'),(N'C'),(N'D'),(N'E'))f(fila) CROSS JOIN(VALUES(1),(2),(3),(4),(5),(6),(7),(8))n(num)
WHERE c.activo=1 AND NOT EXISTS(SELECT 1 FROM numero_de_asientos a WHERE a.id_sala=s.id_sala AND a.fila=f.fila AND a.numero_asiento=CONVERT(nvarchar(5),n.num));
IF NOT EXISTS(SELECT 1 FROM precios_de_boleto WHERE tipo_boleto=N'General CINACH') INSERT precios_de_boleto(tipo_boleto,precio_base) VALUES(N'General CINACH',75);
DECLARE @today date=CONVERT(date,SYSUTCDATETIME() AT TIME ZONE 'UTC' AT TIME ZONE 'Central America Standard Time');
INSERT fechas(fecha_proyeccion,dia_semana) SELECT DATEADD(day,n,@today),DATENAME(weekday,DATEADD(day,n,@today)) FROM(VALUES(0),(1),(2),(3),(4),(5),(6))d(n)
WHERE NOT EXISTS(SELECT 1 FROM fechas f WHERE f.fecha_proyeccion=DATEADD(day,n,@today));
-- Cada pelicula tiene fin segun su duracion y 20 minutos entre funciones.
DECLARE @p int,@mins int,@s int,@f int,@start time,@end time,@h int;
DECLARE shows CURSOR LOCAL FAST_FORWARD FOR
WITH p AS(SELECT id_pelicula,duracion_minutos,ROW_NUMBER()OVER(ORDER BY id_pelicula)rn FROM peliculas WHERE activo=1 AND duracion_minutos<=190),
s AS(SELECT s.id_sala,ROW_NUMBER()OVER(PARTITION BY s.id_cine ORDER BY s.id_sala)rn FROM numero_de_salas s JOIN eleccion_de_cines c ON c.id_cine=s.id_cine WHERE c.activo=1)
SELECT p.id_pelicula,p.duracion_minutos,s.id_sala,f.id_fecha,CONVERT(time,DATEADD(minute,600+((p.rn-1)%4)*210,CAST('20000101' AS datetime)))
FROM p JOIN s ON s.rn=CASE WHEN p.rn<=4 THEN 1 ELSE 2 END CROSS JOIN fechas f
WHERE p.rn<=8 AND f.fecha_proyeccion BETWEEN @today AND DATEADD(day,6,@today);
OPEN shows; FETCH NEXT FROM shows INTO @p,@mins,@s,@f,@start;
WHILE @@FETCH_STATUS=0 BEGIN
 SET @end=DATEADD(minute,@mins,@start);
 IF NOT EXISTS(SELECT 1 FROM cartelera c JOIN horarios_de_peliculas h ON h.id_horario=c.id_horario WHERE c.id_sala=@s AND c.id_fecha=@f AND c.activo=1 AND CAST(@start AS datetime)<DATEADD(minute,20,CAST(h.hora_fin AS datetime)) AND DATEADD(minute,20,CAST(@end AS datetime))>CAST(h.hora_inicio AS datetime))
 BEGIN
  SET @h=NULL; SELECT TOP 1 @h=id_horario FROM horarios_de_peliculas WHERE hora_inicio=@start AND hora_fin=@end;
  IF @h IS NULL BEGIN INSERT horarios_de_peliculas(hora_inicio,hora_fin) VALUES(@start,@end); SET @h=SCOPE_IDENTITY(); END;
  IF NOT EXISTS(SELECT 1 FROM cartelera WHERE id_sala=@s AND id_fecha=@f AND id_horario=@h)
   INSERT cartelera(id_pelicula,id_sala,id_fecha,id_horario,id_precio) SELECT @p,@s,@f,@h,id_precio FROM precios_de_boleto WHERE tipo_boleto=N'General CINACH';
 END;
 FETCH NEXT FROM shows INTO @p,@mins,@s,@f,@start;
END;
CLOSE shows; DEALLOCATE shows;
COMMIT;
