-- CINACH v2. Actualizacion no destructiva. Ejecutar en la base CINACH existente.
-- Conserva usuarios, compras y contraseñas. Los antiguos cines de demostracion se ocultan.
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO
IF COL_LENGTH('dbo.eleccion_de_cines','nombre_sucursal') IS NULL
 ALTER TABLE dbo.eleccion_de_cines ADD nombre_sucursal NVARCHAR(100) NULL;
GO
IF COL_LENGTH('dbo.usuarios','activo') IS NULL ALTER TABLE dbo.usuarios ADD activo BIT NOT NULL CONSTRAINT DF_usuarios_activo DEFAULT 1;
GO
IF COL_LENGTH('dbo.peliculas','activo') IS NULL ALTER TABLE dbo.peliculas ADD activo BIT NOT NULL CONSTRAINT DF_peliculas_activo DEFAULT 1;
GO
IF COL_LENGTH('dbo.cartelera','activo') IS NULL ALTER TABLE dbo.cartelera ADD activo BIT NOT NULL CONSTRAINT DF_cartelera_activo DEFAULT 1;
GO
IF COL_LENGTH('dbo.eleccion_de_cines','activo') IS NULL ALTER TABLE dbo.eleccion_de_cines ADD activo BIT NOT NULL CONSTRAINT DF_eleccion_de_cines_activo DEFAULT 1;
GO
IF COL_LENGTH('dbo.generador_de_ticket','precio_unitario') IS NULL ALTER TABLE dbo.generador_de_ticket ADD precio_unitario DECIMAL(8,2) NULL;
GO
IF COL_LENGTH('dbo.detalle_ticket_asientos','activo') IS NULL ALTER TABLE dbo.detalle_ticket_asientos ADD activo BIT NOT NULL CONSTRAINT DF_detalle_activo DEFAULT 1;
GO
IF EXISTS(SELECT 1 FROM sys.key_constraints WHERE name='UQ_detalle_funcion_asiento')
 ALTER TABLE dbo.detalle_ticket_asientos DROP CONSTRAINT UQ_detalle_funcion_asiento;
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE name='UX_asientos_vigentes' AND object_id=OBJECT_ID('dbo.detalle_ticket_asientos'))
 CREATE UNIQUE INDEX UX_asientos_vigentes ON dbo.detalle_ticket_asientos(id_cartelera,id_asiento) WHERE activo=1;
GO
UPDATE dbo.eleccion_de_cines SET activo=0 WHERE nombre_sucursal LIKE N'%demostraci%' OR direccion LIKE N'%ficticia%';
GO
IF NOT EXISTS(SELECT 1 FROM dbo.eleccion_de_cines WHERE nombre_cine=N'Cinépolis' AND nombre_sucursal=N'Poliforum')
 INSERT dbo.eleccion_de_cines(nombre_cine,nombre_sucursal,direccion,ciudad) VALUES(N'Cinépolis',N'Poliforum',N'Blvd. Andrés Serra Rojas 250, Col. El Retiro',N'Tuxtla Gutiérrez');
IF NOT EXISTS(SELECT 1 FROM dbo.eleccion_de_cines WHERE nombre_cine=N'Cinépolis' AND nombre_sucursal=N'Plaza Las Américas')
 INSERT dbo.eleccion_de_cines(nombre_cine,nombre_sucursal,direccion,ciudad) VALUES(N'Cinépolis',N'Plaza Las Américas',N'Av. 5ta. Norte Poniente 265, Centro',N'Tuxtla Gutiérrez');
IF NOT EXISTS(SELECT 1 FROM dbo.eleccion_de_cines WHERE nombre_cine=N'Cinemex' AND nombre_sucursal=N'Galerías Tuxtla')
 INSERT dbo.eleccion_de_cines(nombre_cine,nombre_sucursal,direccion,ciudad) VALUES(N'Cinemex',N'Galerías Tuxtla',N'Blvd. Dr. Belisario Domínguez 1861, Fracc. Bugambilias',N'Tuxtla Gutiérrez');
IF NOT EXISTS(SELECT 1 FROM dbo.eleccion_de_cines WHERE nombre_cine=N'Cinemex' AND nombre_sucursal=N'Ámbar Fashion Mall')
 INSERT dbo.eleccion_de_cines(nombre_cine,nombre_sucursal,direccion,ciudad) VALUES(N'Cinemex',N'Ámbar Fashion Mall',N'Carr. Tuxtla-Chiapa de Corzo 651, esq. Blvd. Salomón González Blanco',N'Tuxtla Gutiérrez');
IF NOT EXISTS(SELECT 1 FROM dbo.eleccion_de_cines WHERE nombre_cine=N'Cinemex' AND nombre_sucursal=N'Ámbar Fashion Mall Platino')
 INSERT dbo.eleccion_de_cines(nombre_cine,nombre_sucursal,direccion,ciudad) VALUES(N'Cinemex',N'Ámbar Fashion Mall Platino',N'Carr. Tuxtla-Chiapa de Corzo 651, esq. Blvd. Salomón González Blanco',N'Tuxtla Gutiérrez');
GO
CREATE OR ALTER PROCEDURE sp_ListarPeliculas
    @genero NVARCHAR(30) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT p.id_pelicula, p.titulo, c.nombre_categoria AS genero,
           p.duracion_minutos, p.clasificacion, p.sinopsis, p.poster_url
    FROM peliculas p
    INNER JOIN categoria_de_peliculas c ON c.id_categoria = p.id_categoria
    WHERE p.activo=1 AND (@genero IS NULL OR c.nombre_categoria = @genero)
    ORDER BY p.id_pelicula;
END;
GO
CREATE OR ALTER PROCEDURE sp_ProcesarCompraConTarjeta
    @id_usuario      INT,
    @correo_contacto NVARCHAR(100),
    @id_cartelera    INT,
    @id_forma_pago   INT,
    @numero_tarjeta  NVARCHAR(25),
    @titular_tarjeta NVARCHAR(100),
    @lista_asientos  NVARCHAR(MAX),
    @id_promocion    INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
    BEGIN TRANSACTION;
    DECLARE @lock INT;
    EXEC @lock=sys.sp_getapplock @Resource=N'CINACH_OPERACIONES',@LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=10000;
    IF @lock < 0 THROW 50029,N'Operacion ocupada. Intenta nuevamente.',1;
    IF NOT EXISTS (
      SELECT 1 FROM cartelera c JOIN fechas f ON f.id_fecha=c.id_fecha
      JOIN horarios_de_peliculas h ON h.id_horario=c.id_horario
      JOIN peliculas p ON p.id_pelicula=c.id_pelicula
      JOIN numero_de_salas s ON s.id_sala=c.id_sala JOIN eleccion_de_cines ci ON ci.id_cine=s.id_cine
      WHERE c.id_cartelera=@id_cartelera AND c.activo=1 AND p.activo=1 AND ci.activo=1
      AND DATEADD(SECOND,DATEDIFF(SECOND,CAST('00:00' AS time),h.hora_inicio),CAST(f.fecha_proyeccion AS datetime2))
      > CAST(SYSUTCDATETIME() AT TIME ZONE 'UTC' AT TIME ZONE 'Central America Standard Time' AS datetime2))
      THROW 50027,N'La funcion ya comenzo o no esta disponible.',1;
    -- Validaciones dentro de la misma transaccion.
    DECLARE @asientos TABLE (id_asiento INT PRIMARY KEY);
    INSERT INTO @asientos (id_asiento)
    SELECT DISTINCT TRY_CAST(LTRIM(RTRIM(value)) AS INT)
    FROM STRING_SPLIT(@lista_asientos, N',')
    WHERE TRY_CAST(LTRIM(RTRIM(value)) AS INT) IS NOT NULL;

    DECLARE @n_asientos INT = (SELECT COUNT(*) FROM @asientos);
    IF @n_asientos < 1 OR @n_asientos > 8
        THROW 50020, N'Debes seleccionar al menos un asiento.', 1;

    IF NOT EXISTS (SELECT 1 FROM usuarios WHERE id_usuario = @id_usuario AND activo=1)
        THROW 50021, N'El usuario no existe.', 1;

    DECLARE @precio DECIMAL(8,2) =
        (SELECT pb.precio_base
         FROM cartelera c
         INNER JOIN precios_de_boleto pb ON pb.id_precio = c.id_precio
         WHERE c.id_cartelera = @id_cartelera);
    IF @precio IS NULL
        THROW 50022, N'La función seleccionada no existe.', 1;

    IF NOT EXISTS (SELECT 1 FROM forma_de_pago WHERE id_forma_pago = @id_forma_pago)
        THROW 50023, N'La forma de pago no existe.', 1;

    -- todos los asientos deben ser de la sala de esa función
    DECLARE @asientos_de_la_sala INT =
        (SELECT COUNT(*)
         FROM @asientos x
         INNER JOIN numero_de_asientos a ON a.id_asiento = x.id_asiento
         INNER JOIN cartelera c          ON c.id_sala = a.id_sala AND c.id_cartelera = @id_cartelera);
    IF @asientos_de_la_sala <> @n_asientos
        THROW 50024, N'Uno o más asientos no pertenecen a la sala de la función.', 1;

    IF EXISTS (SELECT 1
               FROM detalle_ticket_asientos d
               INNER JOIN @asientos x ON x.id_asiento = d.id_asiento
               WHERE d.id_cartelera = @id_cartelera AND d.activo=1)
        THROW 50025, N'Uno o más asientos ya están ocupados para esta función.', 1;

    DECLARE @descuento DECIMAL(5,2) = 0;
    IF @id_promocion IS NOT NULL
    BEGIN
        DECLARE @aplica_unach BIT;
        SELECT @descuento = porcentaje_descuento, @aplica_unach = aplica_estudiante_unach
        FROM promociones
        WHERE id_promocion = @id_promocion;

        IF @aplica_unach IS NULL
            THROW 50026, N'La promoción no existe.', 1;
        IF @aplica_unach=1 THROW 50026,N'La verificacion universitaria no esta habilitada para esta promocion.',1;
    END

    DECLARE @digitos NVARCHAR(25) = REPLACE(REPLACE(@numero_tarjeta, N' ', N''), N'-', N'');
    IF @digitos <> N'4242424242424242'
        THROW 50028, N'El número de tarjeta no es válido.', 1;

    DECLARE @tarjeta_mascara NVARCHAR(20) = N'**** **** **** ' + RIGHT(@digitos, 4);
    DECLARE @total DECIMAL(8,2) = ROUND(@precio * @n_asientos * (1 - @descuento / 100.0), 2);

    -- ---- Operación ----


        DECLARE @folio NVARCHAR(12) =
            N'CN' + UPPER(SUBSTRING(REPLACE(CONVERT(NVARCHAR(36), NEWID()), N'-', N''), 1, 10));
        DECLARE @codigo_auth NVARCHAR(20) =
            N'AUTH-' + CAST(ABS(CONVERT(BIGINT,CHECKSUM(NEWID()))) % 900000 + 100000 AS NVARCHAR(6));

        INSERT INTO generador_de_ticket
            (folio_alfanumerico, correo_contacto, total_pagado,
             id_usuario, id_cartelera, id_forma_pago, id_promocion, precio_unitario, fecha_emision)
        VALUES
            (@folio, @correo_contacto, @total,
             @id_usuario, @id_cartelera, @id_forma_pago, @id_promocion, @precio, CAST(SYSUTCDATETIME() AT TIME ZONE 'UTC' AT TIME ZONE 'Central America Standard Time' AS datetime2));

        DECLARE @id_ticket INT = SCOPE_IDENTITY();

        INSERT INTO detalle_ticket_asientos (id_ticket, id_asiento, id_cartelera)
        SELECT @id_ticket, id_asiento, @id_cartelera FROM @asientos;

        INSERT INTO transacciones_tarjeta
            (id_ticket, numero_tarjeta_enmascarado, titular_tarjeta, codigo_autorizacion, estado_pago)
        VALUES
            (@id_ticket, @tarjeta_mascara, @titular_tarjeta, @codigo_auth, N'APROBADO');

        COMMIT TRANSACTION;

        SELECT @id_ticket   AS id_ticket,
               @folio       AS FolioGenerado,
               @codigo_auth AS CodigoAutorizacion,
               @total       AS TotalPagado,
               N'Compra exitosa' AS Mensaje;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        EXEC sp_RegistrarError;
        THROW;
    END CATCH
END;
GO
CREATE OR ALTER PROCEDURE sp_CancelarTicket
    @folio_alfanumerico NVARCHAR(12)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @id_ticket INT =
        (SELECT id_ticket FROM generador_de_ticket WHERE folio_alfanumerico = @folio_alfanumerico);

    IF @id_ticket IS NULL
        THROW 50030, N'El folio especificado no existe en el sistema.', 1;
    IF EXISTS (SELECT 1 FROM transacciones_tarjeta WHERE id_ticket = @id_ticket AND estado_pago = N'CANCELADO')
        THROW 50031, N'El ticket ya fue cancelado.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        UPDATE detalle_ticket_asientos SET activo=0 WHERE id_ticket = @id_ticket;

        UPDATE transacciones_tarjeta
        SET estado_pago = N'CANCELADO'
        WHERE id_ticket = @id_ticket;

        COMMIT TRANSACTION;
        SELECT N'El ticket ha sido cancelado correctamente.' AS Resultado;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        EXEC sp_RegistrarError;
        THROW;
    END CATCH
END;
GO
CREATE OR ALTER PROCEDURE sp_ReporteVentasPorPelicula AS
BEGIN
 SET NOCOUNT ON;
 SELECT p.titulo Pelicula,COUNT(t.id_ticket) Compras,
 COALESCE(SUM(a.boletos),0) Total_Boletos_Vendidos,COALESCE(SUM(t.total_pagado),0) Ingresos_Totales
 FROM peliculas p LEFT JOIN cartelera c ON c.id_pelicula=p.id_pelicula
 LEFT JOIN generador_de_ticket t ON t.id_cartelera=c.id_cartelera
 AND EXISTS(SELECT 1 FROM transacciones_tarjeta tt WHERE tt.id_ticket=t.id_ticket AND tt.estado_pago=N'APROBADO')
 OUTER APPLY(SELECT COUNT(*) boletos FROM detalle_ticket_asientos d WHERE d.id_ticket=t.id_ticket AND d.activo=1) a
 GROUP BY p.id_pelicula,p.titulo ORDER BY Ingresos_Totales DESC;
END;
GO
PRINT N'CINACH actualizado. Ejecuta 02_Programacion_Inicial.sql si necesitas funciones iniciales.';
GO

CREATE OR ALTER PROCEDURE sp_ObtenerUsuarioPorCorreo @correo NVARCHAR(100) AS
BEGIN
 SET NOCOUNT ON;
 SELECT id_usuario,nombre,correo,rol,activo,contrasena contrasena_hash FROM usuarios WHERE correo=LOWER(LTRIM(RTRIM(@correo)));
END;
GO
