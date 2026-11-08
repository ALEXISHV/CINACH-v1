/* CINACH - Habilitar cuenta administradora sin crear contraseñas predeterminadas.
   1) Registra primero una cuenta normal desde registro.html.
   2) Sustituye el correo de ejemplo por el correo exacto de esa cuenta.
   3) Ejecuta este script conectado a la base de datos CINACH de Somee.
   La contraseña sigue siendo la que el usuario registró; nunca se guarda aquí.
*/
SET NOCOUNT ON;
DECLARE @CorreoAdmin NVARCHAR(100) = N'cambia-este-correo@ejemplo.com';

IF NOT EXISTS (SELECT 1 FROM dbo.usuarios WHERE correo = @CorreoAdmin)
BEGIN
    THROW 51001, 'No existe una cuenta con ese correo. Registra primero al usuario administrador.', 1;
END;

UPDATE dbo.usuarios
SET rol = N'admin', activo=1
WHERE correo = @CorreoAdmin;

SELECT id_usuario, nombre, correo, rol
FROM dbo.usuarios
WHERE correo = @CorreoAdmin;
