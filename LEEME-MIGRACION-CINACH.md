# CINACH - Compra simulada (actualización)

## Qué se agregó
- Flujo de compra: cadena (Cinépolis/Cinemex), película, sucursal, función, asientos y pago de demostración.
- Consulta de disponibilidad de asientos desde SQL Server.
- Compra transaccional mediante `sp_ProcesarCompraConTarjeta`.
- Ticket digital con folio y opción de imprimir/guardar como PDF.
- Envío opcional del ticket por SMTP.
- Datos iniciales de sucursales, salas, asientos y horarios de demostración.

## IMPORTANTE: credenciales
Se eliminó del `appsettings.json` la cadena de conexión que estaba incluida en el ZIP original. Esa contraseña debe considerarse expuesta: cámbiala desde el panel de Somee antes de publicar.
Configura la conexión mediante una variable de entorno, no dentro de archivos públicos:

Windows PowerShell (solo para la sesión actual):
```powershell
$env:ConnectionStrings__Cinach="Server=SERVIDOR;Database=BASE;User Id=USUARIO;Password=NUEVA_CONTRASENA;Encrypt=True;TrustServerCertificate=True;"
```

En Somee configura la cadena en el mecanismo de configuración/variables que admita tu plan. No subas contraseñas a Git ni compartas capturas que las muestren.

## Base de datos existente en Somee
1. Haz un respaldo antes de cualquier cambio.
2. Abre SSMS y conéctate a la base CINACH de Somee.
3. Abre `Base de datos Cinach/Cinach_Compra_Upgrade.sql`.
4. Verifica que la ventana de consulta esté conectada a la base CINACH correcta.
5. Ejecuta el script una sola vez. Es idempotente y no borra tablas ni compras existentes.
6. Comprueba que existan cadenas Cinépolis y Cinemex, salas, asientos y funciones futuras.

Las sucursales y direcciones del script son ficticias para demostración académica, no representan ubicaciones oficiales ni disponibilidad real de las cadenas.

## Tarjeta de prueba
- Número de prueba: `4242 4242 4242 4242`
- No se solicita CVV ni vencimiento.
- El backend solo acepta esa tarjeta ficticia y manda un valor fijo al procedimiento SQL.
- Nunca introduzcas una tarjeta bancaria real. No hay pasarela ni cobro real.
- SQL Server solo almacena los últimos cuatro dígitos enmascarados y el titular; nunca se almacena CVV.

## Correo SMTP (opcional)
Completa los valores de `Email` mediante variables de entorno en el hosting:
- `Email__Host`
- `Email__Port` (normalmente 587)
- `Email__EnableSsl` (`true`)
- `Email__User`
- `Email__Password`
- `Email__From`
- `Email__FromName`

Si SMTP no está configurado o falla, la compra no se pierde: el ticket se muestra y se puede imprimir/guardar como PDF. El estado del correo se informa en pantalla.

## Publicación
1. Abre `CINACH.csproj` en Visual Studio.
2. Publica en carpeta en configuración Release y destino compatible con el hosting de Somee.
3. Comprueba que el resultado incluya `web.config`, `CINACH.dll`, `CINACH.deps.json`, `CINACH.runtimeconfig.json` y `wwwroot`.
4. Sube el contenido publicado a la raíz del sitio mediante FTP.
5. Configura la cadena de conexión y, si se desea, SMTP en el hosting.
6. Prueba inicio de sesión, compra, asientos ocupados, ticket y correo.

## Endpoints agregados
- `GET /api/cadenas`
- `GET /api/cadenas/{marca}/peliculas`
- `GET /api/cines?marca=Cinépolis|Cinemex`
- `GET /api/funciones?cineId={id}&peliculaId={id}`
- `GET /api/funciones/{id}/asientos`
- `POST /api/compras` (requiere sesión)
- `GET /api/tickets/{folio}` (requiere sesión y propiedad del ticket)

## Nota de consistencia
La restricción única `UQ_detalle_funcion_asiento` en SQL Server evita vender el mismo asiento dos veces para una función. Si dos usuarios intentan comprar simultáneamente el mismo lugar, solo una transacción podrá confirmarse.


## Panel de administración

1. Registra desde la página una cuenta normal con el correo que será administrador.
2. En SSMS, conectado a la base de datos CINACH de Somee, abre `Base de datos Cinach/Cinach_Admin_Upgrade.sql`.
3. Cambia `cambia-este-correo@ejemplo.com` por el correo exacto de la cuenta y ejecuta el script. No compartas la contraseña ni uses credenciales predeterminadas.
4. Cierra sesión e inicia sesión de nuevo para que la cookie recoja el rol `admin`.
5. En la barra de navegación aparecerá **Administración**. El panel permite modificar fecha y hora de funciones.

La API valida el rol en el servidor. Las funciones que ya tienen boletos emitidos no se pueden modificar, y se impide asignar dos funciones a la misma sala, fecha y horario. Para añadir o eliminar administradores, modifica el rol únicamente desde SQL Server y limita el acceso a la cuenta administradora.
