/* CINACH - Ampliación de compra y funciones de demostración
   IMPORTANTE: este script NO elimina tablas ni registros existentes.
   Ejecutar una sola vez en la base CINACH alojada en Somee.
   Las sucursales/direcciones son datos académicos ficticios de demostración.
*/
SET NOCOUNT ON;

IF COL_LENGTH('dbo.eleccion_de_cines', 'nombre_sucursal') IS NULL
    ALTER TABLE dbo.eleccion_de_cines ADD nombre_sucursal NVARCHAR(100) NULL;

-- Completar sucursales anteriores sin alterar los datos de dirección.
UPDATE dbo.eleccion_de_cines
SET nombre_sucursal = COALESCE(nombre_sucursal, N'Sucursal de demostración')
WHERE nombre_sucursal IS NULL;

IF NOT EXISTS (SELECT 1 FROM dbo.eleccion_de_cines WHERE nombre_cine = N'Cinépolis' AND nombre_sucursal = N'Sucursal de demostración - Tuxtla')
    INSERT dbo.eleccion_de_cines(nombre_cine,nombre_sucursal,direccion,ciudad)
    VALUES(N'Cinépolis',N'Sucursal de demostración - Tuxtla',N'Dirección ficticia para pruebas académicas',N'Tuxtla Gutiérrez');

IF NOT EXISTS (SELECT 1 FROM dbo.eleccion_de_cines WHERE nombre_cine = N'Cinemex' AND nombre_sucursal = N'Sucursal de demostración - Tuxtla')
    INSERT dbo.eleccion_de_cines(nombre_cine,nombre_sucursal,direccion,ciudad)
    VALUES(N'Cinemex',N'Sucursal de demostración - Tuxtla',N'Dirección ficticia para pruebas académicas',N'Tuxtla Gutiérrez');

-- Dos salas por sucursal.
INSERT dbo.numero_de_salas(numero_sala,capacidad_asientos,id_cine)
SELECT v.numero_sala,40,c.id_cine
FROM dbo.eleccion_de_cines c
CROSS JOIN (VALUES(N'Sala 1'),(N'Sala 2')) v(numero_sala)
WHERE c.nombre_cine IN (N'Cinépolis',N'Cinemex')
  AND NOT EXISTS (SELECT 1 FROM dbo.numero_de_salas s WHERE s.id_cine=c.id_cine AND s.numero_sala=v.numero_sala);

-- 40 asientos por sala: filas A-E, lugares 1-8.
INSERT dbo.numero_de_asientos(numero_asiento,fila,id_sala)
SELECT CONVERT(NVARCHAR(5),n.numero), f.fila, s.id_sala
FROM dbo.numero_de_salas s
CROSS JOIN (VALUES(N'A'),(N'B'),(N'C'),(N'D'),(N'E')) f(fila)
CROSS JOIN (VALUES(1),(2),(3),(4),(5),(6),(7),(8)) n(numero)
WHERE NOT EXISTS (SELECT 1 FROM dbo.numero_de_asientos a WHERE a.id_sala=s.id_sala AND a.fila=f.fila AND a.numero_asiento=CONVERT(NVARCHAR(5),n.numero));

-- Próximos siete días (incluye hoy), cuatro horarios de demostración.
;WITH dias AS (
    SELECT 0 n UNION ALL SELECT n+1 FROM dias WHERE n<6
)
INSERT dbo.fechas(fecha_proyeccion,dia_semana)
SELECT DATEADD(DAY,n,CONVERT(date,GETDATE())),
       CASE ((DATEPART(WEEKDAY,DATEADD(DAY,n,CONVERT(date,GETDATE())))+@@DATEFIRST-2)%7)
         WHEN 0 THEN N'Lunes' WHEN 1 THEN N'Martes' WHEN 2 THEN N'Miércoles'
         WHEN 3 THEN N'Jueves' WHEN 4 THEN N'Viernes' WHEN 5 THEN N'Sábado' ELSE N'Domingo' END
FROM dias d
WHERE NOT EXISTS (SELECT 1 FROM dbo.fechas f WHERE f.fecha_proyeccion=DATEADD(DAY,d.n,CONVERT(date,GETDATE())))
OPTION (MAXRECURSION 7);

INSERT dbo.horarios_de_peliculas(hora_inicio,hora_fin)
SELECT v.inicio,v.fin
FROM (VALUES (CONVERT(time,'13:00'),CONVERT(time,'15:00')),
             (CONVERT(time,'16:00'),CONVERT(time,'18:00')),
             (CONVERT(time,'19:00'),CONVERT(time,'21:00')),
             (CONVERT(time,'21:30'),CONVERT(time,'23:30'))) v(inicio,fin)
WHERE NOT EXISTS (SELECT 1 FROM dbo.horarios_de_peliculas h WHERE h.hora_inicio=v.inicio);

IF NOT EXISTS (SELECT 1 FROM dbo.precios_de_boleto WHERE tipo_boleto=N'General - demostración')
    INSERT dbo.precios_de_boleto(tipo_boleto,precio_base) VALUES(N'General - demostración',75.00);

-- Funciones: ocho películas por día y sucursal, distribuidas en dos salas.
;WITH peliculas AS (
    SELECT id_pelicula, ROW_NUMBER() OVER(ORDER BY id_pelicula) rn FROM dbo.peliculas
), salas AS (
    SELECT id_sala,id_cine,ROW_NUMBER() OVER(PARTITION BY id_cine ORDER BY id_sala) rn FROM dbo.numero_de_salas
), horarios AS (
    SELECT id_horario,ROW_NUMBER() OVER(ORDER BY hora_inicio) rn FROM dbo.horarios_de_peliculas WHERE hora_inicio IN (CONVERT(time,'13:00'),CONVERT(time,'16:00'),CONVERT(time,'19:00'),CONVERT(time,'21:30'))
), combinaciones AS (
    SELECT f.id_fecha,p.id_pelicula,p.rn, s.id_sala,h.id_horario
    FROM dbo.fechas f
    CROSS JOIN peliculas p
    INNER JOIN salas s ON s.rn=CASE WHEN p.rn<=4 THEN 1 ELSE 2 END
    INNER JOIN horarios h ON h.rn=((p.rn-1)%4)+1
    WHERE f.fecha_proyeccion>=CONVERT(date,GETDATE())
)
INSERT dbo.cartelera(id_fecha,id_pelicula,id_horario,id_sala,id_precio)
SELECT x.id_fecha,x.id_pelicula,x.id_horario,x.id_sala,pr.id_precio
FROM combinaciones x
CROSS JOIN dbo.precios_de_boleto pr
WHERE pr.tipo_boleto=N'General - demostración'
  AND NOT EXISTS (SELECT 1 FROM dbo.cartelera c WHERE c.id_fecha=x.id_fecha AND c.id_pelicula=x.id_pelicula AND c.id_horario=x.id_horario AND c.id_sala=x.id_sala);

PRINT N'Actualización CINACH completada. Revisa las sucursales y funciones de demostración.';
