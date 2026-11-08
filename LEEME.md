# CINACH — Actualización integral

Incluye el código fuente actualizado. NO contiene una publicación precompilada ni credenciales.
Se mantiene ASP.NET Core 8 + SQL Server + HTML/CSS/JavaScript, con Bootstrap local.

## 1. Actualizar tu base EXISTENTE en Somee

1. Conserva una copia de tus archivos anteriores y un respaldo de la base si tu alojamiento lo permite.
2. Abre SSMS y conéctate al servidor de Somee como ya lo hacías.
3. Selecciona TU BASE existente en la lista de bases de la ventana de consulta. No uses master.
4. Abre `sql/01_Actualizar.sql` y ejecuta TODO el archivo (F5), incluyendo los separadores GO.
5. Comprueba que no haya errores. Este archivo conserva usuarios, contraseñas y compras. Agrega campos y reemplaza procedimientos; oculta sucursales ficticias sin borrar sus tickets.
6. Ejecuta `sql/02_Programacion_Inicial.sql` si deseas disponer de funciones para los próximos siete días. Agrega sucursales/salas/asientos de trabajo y programación interna; no consulta las carteleras de las cadenas. Puedes ejecutarlo nuevamente para fechas futuras. No borra compras.
7. NO ejecutes los viejos `Cinach.sql` o `Cinach_Somee.sql`: los anteriores tenían reinicio destructivo activado.
8. NO ejecutes `00_Solo_Base_Nueva.sql` sobre tu base existente. Ese archivo es únicamente para instalar en una base VACÍA, seguido de 01 y 02.

La migración agrega nombre_sucursal en un lote separado (GO) antes de utilizarlo, evitando el error de columna que aparecía en la versión anterior.

## 2. Configurar y ejecutar localmente

1. Descomprime este ZIP en una carpeta nueva. No mezcles bin/obj/publish antiguos con el código nuevo.
2. Instala o utiliza el SDK de .NET 8 que ya usas para el proyecto.
3. Copia `appsettings.Production.example.json` con el nombre `appsettings.Production.json`.
4. Completa `ConnectionStrings:Cinach` con servidor, base, usuario y contraseña de tu cuenta Somee. Puedes tomar esos valores de TU archivo anterior. No publiques el archivo en GitHub.
5. La plantilla propone cifrado con certificado verificado. Usa el nombre de servidor que indique Somee. Si el proveedor no ofrece certificado válido, revisa su configuración; no desactives el cifrado automáticamente.
6. Abre una terminal en la carpeta donde está `CINACH.csproj` y ejecuta:

```powershell
$env:ASPNETCORE_ENVIRONMENT="Production"
dotnet run --urls http://localhost:5090
```

7. Abre http://localhost:5090. No abras los HTML con doble clic ni Live Server: la API necesita ASP.NET Core.
8. La cadena de conexión incluida está vacía intencionalmente. El proyecto no puede consultar datos hasta que completes el archivo Production o la variable de entorno `ConnectionStrings__Cinach`.

## 3. Publicar en Somee

1. Termina primero los pasos de SQL y la prueba local.
2. Dentro de la carpeta del proyecto ejecuta:

```powershell
dotnet publish CINACH.csproj -c Release -o publish
```

También puedes ejecutar `./PUBLICAR.ps1` desde PowerShell: verifica la configuración y publica.
3. Verifica que `publish` incluya `CINACH.dll`, `CINACH.deps.json`, `CINACH.runtimeconfig.json`, `web.config`, `wwwroot`, las dependencias y `appsettings.Production.json`.
4. En Somee detén temporalmente el sitio si el panel lo permite, para reemplazar DLL sin que estén bloqueadas.
5. Sube el CONTENIDO de `publish` a la raíz del sitio. No subas la carpeta contenedora `publish` ni el código fuente ni SQL. Sustituye los archivos de la publicación anterior.
6. Conserva la configuración de alojamiento de ASP.NET Core/.NET 8. Reactiva el sitio.
7. Abre el sitio y recarga con Ctrl+F5. Cierra sesión e inicia nuevamente para cargar roles actualizados.

Si PUBLICAR falla, no uses binarios anteriores con la web nueva. Corrige el mensaje de compilación y vuelve a publicar.

## 4. Habilitar tu administrador

1. Registra una cuenta desde la web con tu correo y una contraseña propia.
2. En SSMS abre `sql/03_Habilitar_Admin.sql`.
3. Cambia SOLO el correo de esta línea por el que acabas de registrar:

```sql
DECLARE @CorreoAdmin NVARCHAR(100) = N'tu-correo@ejemplo.com';
```

4. Ejecuta el archivo sobre la MISMA base que utiliza el sitio.
5. La consulta final debe mostrar tu correo, nombre y `rol = admin`.
6. Cierra tu sesión en CINACH e inicia nuevamente. Aparecerá el botón Administración.
7. Abre Administración o entra a `/admin.html` dentro de tu sitio.
8. No existe una contraseña universal de administrador. Usas la contraseña que elegiste al registrar la cuenta. El script no la cambia.

## 5. Prueba completa para presentar

### Catálogos
- En Películas crea "Película de evaluación", con categoría existente, clasificación B y duración 100.
- Déjala sin póster si no has agregado una imagen. Edita título/sinopsis y comprueba que el cambio aparece en cartelera.
- En Funciones crea una función para mañana en una sala disponible; selecciona película, tarifa y hora. El fin se calcula automáticamente.
- Intenta crear otra en esa sala a la misma hora o durante los 20 minutos posteriores a su fin. Debe rechazarse por cruce.
- Edita la función sin compras: debe guardar. Da de baja una función sin tickets y comprueba que desaparece del flujo de compra.
- En Usuarios crea una cuenta de alumno con correo distinto y contraseña válida. Edita su nombre y desactívala: debe impedir un nuevo acceso. Actívala para continuar.
- Las bajas son lógicas: conservan el historial. El administrador no puede quitarse a sí mismo el acceso ni dejar el sistema sin administradores activos.

### Compra y dashboard
- Abre una ventana de incógnito e inicia sesión con el alumno.
- Pulsa Ver funciones en una película: se conserva la selección al elegir la cadena que la ofrece.
- Elige sucursal, función futura y DOS asientos. El ocupado no debe poder seleccionarse.
- Revisa el carrito, vuelve y cambia un asiento; revisa el total actualizado.
- Escribe un nombre y confirma. La tarjeta académica fija es de solo lectura; no ingreses datos bancarios personales.
- Anota el folio, abre Mis compras y recupera el ticket. Usa Imprimir / Guardar PDF.
- Regresa al administrador: en Resumen selecciona las fechas de hoy. La variación respecto al valor anterior debe ser 1 compra y 2 boletos. El ingreso aumenta por el total de esa compra, no por el doble.
- Intenta modificar la función vendida: debe rechazarse.
- En otra sesión intenta los mismos asientos: deben figurar ocupados. Para probar concurrencia, selecciona los mismos asientos en dos sesiones antes de confirmar; solo una compra debe aceptarse.
- Con el alumno abre `/admin.html`: debe mostrar que no tienes permisos. La API también restringe las operaciones administrativas.
- Cierra sesión e intenta consultar el ticket: debe pedir inicio de sesión. Otro usuario no puede consultar un folio ajeno.

## 6. Sucursales incluidas y alcance

Nombres/direcciones contrastados con el directorio del Sistema de Información Cultural, Secretaría de Cultura, consultado el 4 de noviembre de 2026:
https://sic.gob.mx/lista.php?estado_id=7&municipio_id=101&table=comp_cine

- Cinépolis Poliforum — Blvd. Andrés Serra Rojas 250, Col. El Retiro.
- Cinépolis Plaza Las Américas — Av. 5ta. Norte Poniente 265, Centro.
- Cinemex Galerías Tuxtla — Blvd. Dr. Belisario Domínguez 1861, Fracc. Bugambilias.
- Cinemex Ámbar Fashion Mall — Carr. Tuxtla-Chiapa de Corzo 651, esq. Blvd. Salomón González Blanco.
- Cinemex Ámbar Fashion Mall Platino — mismo centro comercial, modalidad distinta.

Se incluyen estas cinco entradas verificadas; no se afirma que el listado sea exhaustivo. Las sucursales son reales. Las salas, planos de asientos, precios y funciones generados por 02 pertenecen al ejercicio de CINACH: no son inventarios comerciales oficiales. No hay integración ni convenio declarado con Cinépolis o Cinemex.

Se retiraron los avisos repetitivos de demostración del recorrido. Se conserva una nota discreta en confirmación y ticket: no se realizan cargos ni se emiten entradas válidas en los cines. Para vender entradas reales se necesita integración autorizada y una pasarela de pago.

## 7. Qué cambió y qué queda fuera

- Inicio sin pósteres: carrusel manual de tres paneles, sin movimiento automático.
- CRUD web de películas, usuarios y funciones, con bajas lógicas.
- Estadísticas por rango de fechas, boletos/compra separados, ranking e impresión.
- Mis compras y reimpresión del ticket.
- Validación de sesión en servidor, permisos, comprobación de cuenta activa y protección básica de solicitudes de otro origen.
- Inicio de sesión limitado por intentos/IP. Contraseñas con PBKDF2 y sal.
- Compras y cambios de programación coordinados mediante transacción/bloqueo; no se venden funciones iniciadas; se evita el doble asiento.
- Se conservan detalles al cancelar desde el procedimiento SQL nuevo. Las cancelaciones anteriores, cuyos detalles ya fueron borrados, no se pueden reconstruir automáticamente.
- Total y precio unitario registrados en la compra; los registros antiguos conservan su total original y precio unitario desconocido (NULL).
- Horas de programación y nuevas emisiones: Tuxtla (UTC−6). Las fechas históricas no se reinterpretan, pues no se conoce la zona que utilizaba el servidor anterior.
- Dependencias de presentación locales: Bootstrap y QR. Se retiró la carga externa de fuentes para reducir fallos de red.

Pendiente fuera de esta entrega: cobros reales, verificación de matrícula, promociones universitarias habilitadas, CRUD de todos los catálogos auxiliares (salas/tarifas/categorías), recuperación de contraseña, y cancelación desde interfaz. Correo opcional: requiere configurar SMTP. No se promete el envío si no está configurado.

## 8. Validación realizada

- C# compilado con referencias de ASP.NET Core/.NET 8: sin errores.
- Sintaxis de los cuatro scripts SQL comprobada con Microsoft ScriptDom. Esto no sustituye ejecutarlos sobre SQL Server.
- Inicio de aplicación y respuestas de acceso sin sesión probadas localmente; validación de datos y rechazo de mutaciones de otro origen.
- Pruebas de navegador con respuestas API controladas: carrusel, ausencia de pósteres en inicio, dashboard, formularios CRUD, guardado, película preseleccionada, asientos ocupados, total, compra, historial, ticket y acceso no administrativo.
- Inspección visual de inicio, dashboard, ticket y diseño móvil.
- NO se ejecutaron migraciones ni compras contra Somee. Tampoco se modificó tu alojamiento. Debes realizar las pruebas del apartado 5 sobre tu instalación.
- Este ZIP contiene fuente. Compila/publica en tu equipo para producir sus propios archivos de dependencias; no reutilices CINACH.dll/deps.json antiguos.
