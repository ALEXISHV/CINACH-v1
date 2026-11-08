/* =====================================================================
   CINACH - Base de datos completa
   Motor: SQL Server 2017 o superior (usa STRING_AGG y STRING_SPLIT)

   QUÉ HACE ESTE SCRIPT (en este orden):
     1. (Opcional) reinicia la base: borra y vuelve a crear todo
     2. Tablas, llaves y restricciones (CHECK / UNIQUE)
     3. Tabla de bitácora de errores
     4. Vista para el correo del ticket
     5. Procedimientos almacenados (con TRY/CATCH y bitácora)
     6. Datos iniciales (categorías, películas y formas de pago)

   CÓMO USARLO: ejecuta este archivo completo (F5) sobre la base que creaste
   en el panel de Somee; aquí no se crea ni se elige ninguna base. Los usuarios/permisos van en el otro archivo:
   Cinach_Usuarios_BD.sql
   ===================================================================== */

-- (En Somee se ejecuta directamente sobre la base que creaste en el panel)

/* ---------------------------------------------------------------------
   1. REINICIO  >>> BORRA TODOS LOS DATOS <<<
   Déjalo en 1 la primera vez (o si una ejecución anterior falló a medias).
   Cámbialo a 0 si ya tienes datos que quieres conservar.
   --------------------------------------------------------------------- */
DECLARE @reiniciar BIT = 1;

IF @reiniciar = 1
BEGIN
    IF OBJECT_ID('v_DetalleTicketParaCorreo', 'V') IS NOT NULL DROP VIEW v_DetalleTicketParaCorreo;
    IF OBJECT_ID('detalle_ticket_asientos', 'U') IS NOT NULL DROP TABLE detalle_ticket_asientos;
    IF OBJECT_ID('transacciones_tarjeta', 'U')   IS NOT NULL DROP TABLE transacciones_tarjeta;
    IF OBJECT_ID('generador_de_ticket', 'U')     IS NOT NULL DROP TABLE generador_de_ticket;
    IF OBJECT_ID('cartelera', 'U')               IS NOT NULL DROP TABLE cartelera;
    IF OBJECT_ID('numero_de_asientos', 'U')      IS NOT NULL DROP TABLE numero_de_asientos;
    IF OBJECT_ID('numero_de_salas', 'U')         IS NOT NULL DROP TABLE numero_de_salas;
    IF OBJECT_ID('eleccion_de_cines', 'U')       IS NOT NULL DROP TABLE eleccion_de_cines;
    IF OBJECT_ID('peliculas', 'U')               IS NOT NULL DROP TABLE peliculas;
    IF OBJECT_ID('categoria_de_peliculas', 'U')  IS NOT NULL DROP TABLE categoria_de_peliculas;
    IF OBJECT_ID('fechas', 'U')                  IS NOT NULL DROP TABLE fechas;
    IF OBJECT_ID('horarios_de_peliculas', 'U')   IS NOT NULL DROP TABLE horarios_de_peliculas;
    IF OBJECT_ID('precios_de_boleto', 'U')       IS NOT NULL DROP TABLE precios_de_boleto;
    IF OBJECT_ID('promociones', 'U')             IS NOT NULL DROP TABLE promociones;
    IF OBJECT_ID('forma_de_pago', 'U')           IS NOT NULL DROP TABLE forma_de_pago;
    IF OBJECT_ID('usuarios', 'U')                IS NOT NULL DROP TABLE usuarios;
    IF OBJECT_ID('LogErrores', 'U')              IS NOT NULL DROP TABLE LogErrores;
END
GO

/* ---------------------------------------------------------------------
   2. TABLAS
   --------------------------------------------------------------------- */

-- Usuarios. "contrasena" guarda el HASH de la contraseña (nunca el texto).
CREATE TABLE usuarios (
    id_usuario           INT IDENTITY(1,1) CONSTRAINT PK_usuarios PRIMARY KEY,
    nombre               NVARCHAR(100) NOT NULL,
    correo               NVARCHAR(100) NOT NULL CONSTRAINT UQ_usuarios_correo UNIQUE,
    contrasena           NVARCHAR(255) NOT NULL,
    rol                  NVARCHAR(20)  NOT NULL
                         CONSTRAINT DF_usuarios_rol DEFAULT N'estudiante'
                         CONSTRAINT CK_usuarios_rol CHECK (rol IN (N'estudiante', N'docente', N'admin')),
    fecha_registro       DATETIME2     NOT NULL CONSTRAINT DF_usuarios_fecha DEFAULT SYSDATETIME(),
    CONSTRAINT CK_usuarios_correo CHECK (correo LIKE N'%_@_%._%')
);
GO

CREATE TABLE categoria_de_peliculas (
    id_categoria     INT IDENTITY(1,1) CONSTRAINT PK_categoria PRIMARY KEY,
    nombre_categoria NVARCHAR(30)  NOT NULL CONSTRAINT UQ_categoria_nombre UNIQUE,
    descripcion      NVARCHAR(100) NULL
);

CREATE TABLE peliculas (
    id_pelicula      INT IDENTITY(1,1) CONSTRAINT PK_peliculas PRIMARY KEY,
    titulo           NVARCHAR(100) NOT NULL CONSTRAINT UQ_peliculas_titulo UNIQUE,
    sinopsis         NVARCHAR(MAX) NULL,
    duracion_minutos INT           NOT NULL CONSTRAINT CK_peliculas_duracion CHECK (duracion_minutos > 0),
    clasificacion    NVARCHAR(10)  NOT NULL,
    poster_url       NVARCHAR(200) NULL,
    id_categoria     INT           NOT NULL,
    CONSTRAINT FK_peliculas_categoria FOREIGN KEY (id_categoria) REFERENCES categoria_de_peliculas (id_categoria)
);

CREATE TABLE eleccion_de_cines (
    id_cine     INT IDENTITY(1,1) CONSTRAINT PK_cines PRIMARY KEY,
    nombre_cine NVARCHAR(50)  NOT NULL,
    nombre_sucursal NVARCHAR(100) NULL,
    direccion   NVARCHAR(100) NOT NULL,
    ciudad      NVARCHAR(30)  NOT NULL
);

CREATE TABLE numero_de_salas (
    id_sala            INT IDENTITY(1,1) CONSTRAINT PK_salas PRIMARY KEY,
    numero_sala        NVARCHAR(15) NOT NULL,
    capacidad_asientos INT          NOT NULL CONSTRAINT CK_salas_capacidad CHECK (capacidad_asientos > 0),
    id_cine            INT          NOT NULL,
    CONSTRAINT FK_salas_cine FOREIGN KEY (id_cine) REFERENCES eleccion_de_cines (id_cine),
    CONSTRAINT UQ_salas_cine_numero UNIQUE (id_cine, numero_sala)
);

CREATE TABLE numero_de_asientos (
    id_asiento     INT IDENTITY(1,1) CONSTRAINT PK_asientos PRIMARY KEY,
    numero_asiento NVARCHAR(5) NOT NULL,
    fila           NVARCHAR(3) NOT NULL,
    id_sala        INT         NOT NULL,
    CONSTRAINT FK_asientos_sala FOREIGN KEY (id_sala) REFERENCES numero_de_salas (id_sala),
    CONSTRAINT UQ_asientos_sala_fila_numero UNIQUE (id_sala, fila, numero_asiento)
);

CREATE TABLE fechas (
    id_fecha         INT IDENTITY(1,1) CONSTRAINT PK_fechas PRIMARY KEY,
    fecha_proyeccion DATE         NOT NULL CONSTRAINT UQ_fechas_fecha UNIQUE,
    dia_semana       NVARCHAR(15) NOT NULL
);

CREATE TABLE horarios_de_peliculas (
    id_horario  INT IDENTITY(1,1) CONSTRAINT PK_horarios PRIMARY KEY,
    hora_inicio TIME NOT NULL,
    hora_fin    TIME NOT NULL,
    CONSTRAINT CK_horarios_distintos CHECK (hora_fin <> hora_inicio)
);

CREATE TABLE precios_de_boleto (
    id_precio   INT IDENTITY(1,1) CONSTRAINT PK_precios PRIMARY KEY,
    tipo_boleto NVARCHAR(30) NOT NULL CONSTRAINT UQ_precios_tipo UNIQUE,
    precio_base DECIMAL(8,2) NOT NULL CONSTRAINT CK_precios_base CHECK (precio_base > 0)
);

CREATE TABLE promociones (
    id_promocion            INT IDENTITY(1,1) CONSTRAINT PK_promociones PRIMARY KEY,
    nombre_promocion        NVARCHAR(50) NOT NULL,
    porcentaje_descuento    DECIMAL(5,2) NOT NULL
                            CONSTRAINT DF_promo_desc DEFAULT 0.00
                            CONSTRAINT CK_promo_desc CHECK (porcentaje_descuento BETWEEN 0 AND 100),
    aplica_estudiante_unach BIT NOT NULL CONSTRAINT DF_promo_unach DEFAULT 0
);

CREATE TABLE forma_de_pago (
    id_forma_pago INT IDENTITY(1,1) CONSTRAINT PK_forma_pago PRIMARY KEY,
    metodo        NVARCHAR(30) NOT NULL CONSTRAINT UQ_forma_pago_metodo UNIQUE
);

-- Una función = una película en una sala, fecha, horario y precio.
CREATE TABLE cartelera (
    id_cartelera INT IDENTITY(1,1) CONSTRAINT PK_cartelera PRIMARY KEY,
    id_fecha     INT NOT NULL,
    id_pelicula  INT NOT NULL,
    id_horario   INT NOT NULL,
    id_sala      INT NOT NULL,
    id_precio    INT NOT NULL,
    CONSTRAINT FK_cartelera_fecha    FOREIGN KEY (id_fecha)    REFERENCES fechas (id_fecha),
    CONSTRAINT FK_cartelera_pelicula FOREIGN KEY (id_pelicula) REFERENCES peliculas (id_pelicula),
    CONSTRAINT FK_cartelera_horario  FOREIGN KEY (id_horario)  REFERENCES horarios_de_peliculas (id_horario),
    CONSTRAINT FK_cartelera_sala     FOREIGN KEY (id_sala)     REFERENCES numero_de_salas (id_sala),
    CONSTRAINT FK_cartelera_precio   FOREIGN KEY (id_precio)   REFERENCES precios_de_boleto (id_precio),
    -- una sala no puede tener dos funciones a la misma hora el mismo día
    CONSTRAINT UQ_cartelera_sala_fecha_hora UNIQUE (id_sala, id_fecha, id_horario)
);

-- Tablas que faltaban en los scripts originales (las usaban la vista y los procedimientos).
CREATE TABLE generador_de_ticket (
    id_ticket           INT IDENTITY(1,1) CONSTRAINT PK_ticket PRIMARY KEY,
    folio_alfanumerico  NVARCHAR(12)  NOT NULL CONSTRAINT UQ_ticket_folio UNIQUE,
    correo_contacto     NVARCHAR(100) NOT NULL,
    fecha_emision       DATETIME2     NOT NULL CONSTRAINT DF_ticket_fecha DEFAULT SYSDATETIME(),
    total_pagado        DECIMAL(8,2)  NOT NULL CONSTRAINT CK_ticket_total CHECK (total_pagado >= 0),
    id_usuario          INT NOT NULL,
    id_cartelera        INT NOT NULL,
    id_forma_pago       INT NOT NULL,
    id_promocion        INT NULL,
    CONSTRAINT FK_ticket_usuario    FOREIGN KEY (id_usuario)    REFERENCES usuarios (id_usuario),
    CONSTRAINT FK_ticket_cartelera  FOREIGN KEY (id_cartelera)  REFERENCES cartelera (id_cartelera),
    CONSTRAINT FK_ticket_forma_pago FOREIGN KEY (id_forma_pago) REFERENCES forma_de_pago (id_forma_pago),
    CONSTRAINT FK_ticket_promocion  FOREIGN KEY (id_promocion)  REFERENCES promociones (id_promocion)
);

-- Asientos de cada ticket. El UNIQUE (id_cartelera, id_asiento) impide vender
-- dos veces el mismo asiento en la misma función, aunque dos compras lleguen a la vez.
-- Al cancelar un ticket se borran sus filas y el asiento queda libre.
CREATE TABLE detalle_ticket_asientos (
    id_ticket    INT NOT NULL,
    id_asiento   INT NOT NULL,
    id_cartelera INT NOT NULL,
    CONSTRAINT PK_detalle_ticket PRIMARY KEY (id_ticket, id_asiento),
    CONSTRAINT FK_detalle_ticket    FOREIGN KEY (id_ticket)    REFERENCES generador_de_ticket (id_ticket),
    CONSTRAINT FK_detalle_asiento   FOREIGN KEY (id_asiento)   REFERENCES numero_de_asientos (id_asiento),
    CONSTRAINT FK_detalle_cartelera FOREIGN KEY (id_cartelera) REFERENCES cartelera (id_cartelera),
    CONSTRAINT UQ_detalle_funcion_asiento UNIQUE (id_cartelera, id_asiento)
);

-- Solo se guarda la tarjeta ENMASCARADA (últimos 4 dígitos). Nunca el número completo ni el CVV.
CREATE TABLE transacciones_tarjeta (
    id_transaccion             INT IDENTITY(1,1) CONSTRAINT PK_transacciones PRIMARY KEY,
    id_ticket                  INT NOT NULL,
    numero_tarjeta_enmascarado NVARCHAR(20)  NOT NULL,
    titular_tarjeta            NVARCHAR(100) NOT NULL,
    codigo_autorizacion        NVARCHAR(20)  NOT NULL,
    estado_pago                NVARCHAR(10)  NOT NULL
                               CONSTRAINT DF_transacciones_estado DEFAULT N'APROBADO'
                               CONSTRAINT CK_transacciones_estado CHECK (estado_pago IN (N'APROBADO', N'RECHAZADO', N'CANCELADO')),
    fecha_transaccion          DATETIME2 NOT NULL CONSTRAINT DF_transacciones_fecha DEFAULT SYSDATETIME(),
    CONSTRAINT FK_transacciones_ticket FOREIGN KEY (id_ticket) REFERENCES generador_de_ticket (id_ticket)
);
GO

/* ---------------------------------------------------------------------
   3. BITÁCORA DE ERRORES
   --------------------------------------------------------------------- */
CREATE TABLE LogErrores (
    id_error       INT IDENTITY(1,1) CONSTRAINT PK_LogErrores PRIMARY KEY,
    ErrorNumber    INT,
    ErrorSeverity  INT,
    ErrorState     INT,
    ErrorProcedure NVARCHAR(128),
    ErrorLine      INT,
    ErrorMessage   NVARCHAR(4000),
    FechaError     DATETIME2 NOT NULL CONSTRAINT DF_LogErrores_fecha DEFAULT SYSDATETIME()
);
GO

/* ---------------------------------------------------------------------
   4. VISTA PARA EL CORREO DEL TICKET
   --------------------------------------------------------------------- */
CREATE OR ALTER VIEW v_DetalleTicketParaCorreo AS
SELECT
    t.id_ticket,
    t.folio_alfanumerico,
    t.correo_contacto,
    t.total_pagado,
    p.titulo AS pelicula,
    p.poster_url,
    c.nombre_cine,
    c.direccion AS direccion_cine,
    s.numero_sala,
    f.fecha_proyeccion,
    h.hora_inicio,
    STRING_AGG(CONCAT(a.fila, a.numero_asiento), N', ') AS asientos_reservados,
    tt.codigo_autorizacion,
    tt.numero_tarjeta_enmascarado
FROM generador_de_ticket t
INNER JOIN cartelera car              ON t.id_cartelera = car.id_cartelera
INNER JOIN peliculas p                ON car.id_pelicula = p.id_pelicula
INNER JOIN numero_de_salas s          ON car.id_sala = s.id_sala
INNER JOIN eleccion_de_cines c        ON s.id_cine = c.id_cine
INNER JOIN fechas f                   ON car.id_fecha = f.id_fecha
INNER JOIN horarios_de_peliculas h    ON car.id_horario = h.id_horario
INNER JOIN detalle_ticket_asientos dta ON t.id_ticket = dta.id_ticket
INNER JOIN numero_de_asientos a       ON dta.id_asiento = a.id_asiento
LEFT JOIN transacciones_tarjeta tt    ON t.id_ticket = tt.id_ticket
GROUP BY
    t.id_ticket, t.folio_alfanumerico, t.correo_contacto,
    t.total_pagado, p.titulo, p.poster_url, c.nombre_cine, c.direccion,
    s.numero_sala, f.fecha_proyeccion, h.hora_inicio,
    tt.codigo_autorizacion, tt.numero_tarjeta_enmascarado;
GO

/* ---------------------------------------------------------------------
   5. PROCEDIMIENTOS ALMACENADOS
   Regla general: las validaciones del usuario se hacen ANTES del TRY (no
   ensucian la bitácora). Los errores inesperados se guardan en LogErrores
   y se vuelven a lanzar con THROW para que la aplicación se entere.
   --------------------------------------------------------------------- */

-- Guarda en LogErrores el error que se está atendiendo (se llama desde un CATCH).
CREATE OR ALTER PROCEDURE sp_RegistrarError
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO LogErrores (ErrorNumber, ErrorSeverity, ErrorState, ErrorProcedure, ErrorLine, ErrorMessage)
    VALUES (ERROR_NUMBER(), ERROR_SEVERITY(), ERROR_STATE(), ERROR_PROCEDURE(), ERROR_LINE(), ERROR_MESSAGE());
END;
GO

-- REGISTRO. @contrasena debe llegar ya convertida a hash por la aplicación.
CREATE OR ALTER PROCEDURE sp_RegistrarUsuario
    @nombre               NVARCHAR(100),
    @correo               NVARCHAR(100),
    @contrasena           NVARCHAR(255),
    @rol                  NVARCHAR(20) = N'estudiante'
AS
BEGIN
    SET NOCOUNT ON;
    SET @correo = LOWER(LTRIM(RTRIM(@correo)));

    IF EXISTS (SELECT 1 FROM usuarios WHERE correo = @correo)
        THROW 50010, N'El correo electrónico ya se encuentra registrado.', 1;

    BEGIN TRY
        INSERT INTO usuarios (nombre, correo, contrasena, rol)
        VALUES (LTRIM(RTRIM(@nombre)), @correo, @contrasena, @rol);

        SELECT SCOPE_IDENTITY() AS id_usuario_creado;
    END TRY
    BEGIN CATCH
        EXEC sp_RegistrarError;
        THROW;
    END CATCH
END;
GO

-- LOGIN POR CORREO (sin matrícula): devuelve el usuario y su hash; la aplicación compara la contraseña.
CREATE OR ALTER PROCEDURE sp_ObtenerUsuarioPorCorreo
    @correo NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT id_usuario, nombre, correo, rol, contrasena AS contrasena_hash
    FROM usuarios
    WHERE correo = LOWER(LTRIM(RTRIM(@correo)));
END;
GO

-- CATÁLOGO de películas (para la página de cartelera). @genero NULL = todas.
CREATE OR ALTER PROCEDURE sp_ListarPeliculas
    @genero NVARCHAR(30) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT p.id_pelicula, p.titulo, c.nombre_categoria AS genero,
           p.duracion_minutos, p.clasificacion, p.sinopsis, p.poster_url
    FROM peliculas p
    INNER JOIN categoria_de_peliculas c ON c.id_categoria = p.id_categoria
    WHERE @genero IS NULL OR c.nombre_categoria = @genero
    ORDER BY p.id_pelicula;
END;
GO

-- CARTELERA POR CINE (funciones de hoy en adelante)
CREATE OR ALTER PROCEDURE sp_ConsultarCarteleraPorCine
    @id_cine INT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        SELECT
            c.id_cartelera,
            p.titulo AS Pelicula,
            p.clasificacion,
            p.duracion_minutos,
            s.numero_sala,
            f.fecha_proyeccion,
            h.hora_inicio,
            pb.precio_base
        FROM cartelera c
        INNER JOIN peliculas p             ON c.id_pelicula = p.id_pelicula
        INNER JOIN numero_de_salas s       ON c.id_sala = s.id_sala
        INNER JOIN fechas f                ON c.id_fecha = f.id_fecha
        INNER JOIN horarios_de_peliculas h ON c.id_horario = h.id_horario
        INNER JOIN precios_de_boleto pb    ON c.id_precio = pb.id_precio
        WHERE s.id_cine = @id_cine
          AND f.fecha_proyeccion >= CAST(GETDATE() AS DATE)
        ORDER BY f.fecha_proyeccion, h.hora_inicio;
    END TRY
    BEGIN CATCH
        EXEC sp_RegistrarError;
        THROW;
    END CATCH
END;
GO

-- COMPRA CON TARJETA (simulada).
-- El total se calcula aquí (precio de la función x asientos, menos descuento),
-- no se confía en un monto enviado por el cliente. Solo se guardan los últimos 4 dígitos.
-- @lista_asientos: ids de asientos separados por coma, p. ej. N'12,13'.
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

    -- ---- Validaciones (no entran a la bitácora) ----
    DECLARE @asientos TABLE (id_asiento INT PRIMARY KEY);
    INSERT INTO @asientos (id_asiento)
    SELECT DISTINCT TRY_CAST(LTRIM(RTRIM(value)) AS INT)
    FROM STRING_SPLIT(@lista_asientos, N',')
    WHERE TRY_CAST(LTRIM(RTRIM(value)) AS INT) IS NOT NULL;

    DECLARE @n_asientos INT = (SELECT COUNT(*) FROM @asientos);
    IF @n_asientos = 0
        THROW 50020, N'Debes seleccionar al menos un asiento.', 1;

    IF NOT EXISTS (SELECT 1 FROM usuarios WHERE id_usuario = @id_usuario)
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
               WHERE d.id_cartelera = @id_cartelera)
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
        -- Pendiente: validar que sea estudiante UNACH cuando vean usuarios y roles.
    END

    DECLARE @digitos NVARCHAR(25) = REPLACE(REPLACE(@numero_tarjeta, N' ', N''), N'-', N'');
    IF LEN(@digitos) < 12 OR @digitos LIKE N'%[^0-9]%'
        THROW 50028, N'El número de tarjeta no es válido.', 1;

    DECLARE @tarjeta_mascara NVARCHAR(20) = N'**** **** **** ' + RIGHT(@digitos, 4);
    DECLARE @total DECIMAL(8,2) = ROUND(@precio * @n_asientos * (1 - @descuento / 100.0), 2);

    -- ---- Operación ----
    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @folio NVARCHAR(12) =
            N'CINA-' + UPPER(SUBSTRING(REPLACE(CONVERT(NVARCHAR(36), NEWID()), N'-', N''), 1, 6));
        DECLARE @codigo_auth NVARCHAR(20) =
            N'AUTH-' + CAST(ABS(CHECKSUM(NEWID())) % 900000 + 100000 AS NVARCHAR(6));

        INSERT INTO generador_de_ticket
            (folio_alfanumerico, correo_contacto, total_pagado,
             id_usuario, id_cartelera, id_forma_pago, id_promocion)
        VALUES
            (@folio, @correo_contacto, @total,
             @id_usuario, @id_cartelera, @id_forma_pago, @id_promocion);

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

-- CANCELAR TICKET: libera los asientos y marca el pago como CANCELADO
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

        DELETE FROM detalle_ticket_asientos WHERE id_ticket = @id_ticket;

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

-- REPORTE DE VENTAS POR PELÍCULA (solo compras aprobadas, no canceladas)
CREATE OR ALTER PROCEDURE sp_ReporteVentasPorPelicula
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        SELECT
            p.titulo AS Pelicula,
            COUNT(gt.id_ticket) AS Total_Boletos_Vendidos,
            ISNULL(SUM(gt.total_pagado), 0.00) AS Ingresos_Totales
        FROM peliculas p
        LEFT JOIN cartelera c ON p.id_pelicula = c.id_pelicula
        LEFT JOIN generador_de_ticket gt
               ON gt.id_cartelera = c.id_cartelera
              AND EXISTS (SELECT 1 FROM transacciones_tarjeta tt
                          WHERE tt.id_ticket = gt.id_ticket AND tt.estado_pago = N'APROBADO')
        GROUP BY p.id_pelicula, p.titulo
        ORDER BY Ingresos_Totales DESC;
    END TRY
    BEGIN CATCH
        EXEC sp_RegistrarError;
        THROW;
    END CATCH
END;
GO

/* ---------------------------------------------------------------------
   6. DATOS INICIALES
   Las películas son las mismas de la cartelera del sitio; poster_url apunta
   a la carpeta img/posters/ del sitio.
   --------------------------------------------------------------------- */
INSERT INTO categoria_de_peliculas (nombre_categoria, descripcion) VALUES
    (N'Acción',          N'Películas de acción y aventura'),
    (N'Animación',       N'Películas animadas para todo público'),
    (N'Ciencia ficción', N'Películas de ciencia ficción'),
    (N'Drama',           N'Películas dramáticas');

INSERT INTO peliculas (titulo, sinopsis, duracion_minutos, clasificacion, poster_url, id_categoria)
SELECT v.titulo, v.sinopsis, v.duracion, v.clasificacion, v.poster, c.id_categoria
FROM (VALUES
    (N'Interstellar', N'Un grupo de astronautas viaja a través de un agujero de gusano para salvar a la humanidad.', 169, N'B', N'img/posters/interstellar.jpg', N'Ciencia ficción'),
    (N'Blade Runner 2049', N'Un nuevo blade runner descubre un secreto que podría cambiar el orden de la sociedad.', 164, N'B15', N'img/posters/blade-runner-2049.jpg', N'Ciencia ficción'),
    (N'The Dark Knight', N'Batman enfrenta al Joker, quien sume a Ciudad Gótica en el caos.', 152, N'B15', N'img/posters/the-dark-knight.jpg', N'Acción'),
    (N'Mad Max: Furia en el camino', N'Una persecución brutal a través del desierto en busca de libertad.', 120, N'B15', N'img/posters/mad-max.jpg', N'Acción'),
    (N'Coco', N'Miguel viaja a la Tierra de los Muertos para descubrir la historia de su familia.', 105, N'A', N'img/posters/coco.jpg', N'Animación'),
    (N'Spider-Man: Un nuevo universo', N'Miles Morales se convierte en Spider-Man y conoce a otros héroes del multiverso.', 117, N'A', N'img/posters/spider-man.jpg', N'Animación'),
    (N'Parásitos', N'Dos familias de mundos opuestos se entrelazan con consecuencias inesperadas.', 132, N'B15', N'img/posters/Parasite.jpg', N'Drama'),
    (N'Sueño de fuga', N'Un banquero condenado injustamente encuentra esperanza dentro de prisión.', 142, N'B15', N'img/posters/sueno-de-fuga.jpg', N'Drama')
) AS v (titulo, sinopsis, duracion, clasificacion, poster, categoria)
INNER JOIN categoria_de_peliculas c ON c.nombre_categoria = v.categoria;

INSERT INTO forma_de_pago (metodo) VALUES
    (N'Tarjeta de Débito'),
    (N'Tarjeta de Crédito');
GO

-- Comprobación rápida: debe mostrar las 8 películas
EXEC sp_ListarPeliculas;
GO


/* Datos de sucursales, salas, asientos y funciones de demostración.
   Para bases existentes ejecutar Cinach_Compra_Upgrade.sql (no este script completo). */
