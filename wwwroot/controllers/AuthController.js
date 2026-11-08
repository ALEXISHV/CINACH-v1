// CONTROLADOR de registro e inicio de sesión: valida el formulario y usa el modelo Usuario.
import { Usuario } from "../models/Usuario.js?v=cinach-v2";
import { AuthView } from "../views/AuthView.js?v=cinach-v2";

export class AuthController {
  constructor(modo) {
    this.modo = modo; // "registro" o "login"
    this.vista = new AuthView(modo === "registro" ? "formRegistro" : "formLogin");
  }

  async iniciar() {
    // Con una sesión abierta no tiene sentido ver estas pantallas.
    if (await Usuario.sesionActual()) {
      this.vista.redirigir("index.html");
      return;
    }
    this.vista.alEnviar(() => (this.modo === "registro" ? this.registrar() : this.iniciarSesion()));
  }

  async registrar() {
    this.vista.limpiar();
    const datos = this.vista.obtenerDatos();
    const errores = Usuario.validarRegistro(datos);
    if (Object.keys(errores).length > 0) {
      this.vista.mostrarErrores(errores);
      return;
    }

    this.vista.bloquearBoton(true);
    try {
      await Usuario.registrar(datos);
      this.vista.mostrarMensaje("success", "Cuenta creada correctamente. Te llevamos a iniciar sesión...");
      setTimeout(() => this.vista.redirigir("login.html"), 1500);
    } catch (error) {
      this.vista.mostrarMensaje("danger", error.message);
      this.vista.bloquearBoton(false);
    }
  }

  async iniciarSesion() {
    this.vista.limpiar();
    const datos = this.vista.obtenerDatos();
    const errores = Usuario.validarLogin(datos);
    if (Object.keys(errores).length > 0) {
      this.vista.mostrarErrores(errores);
      return;
    }

    this.vista.bloquearBoton(true);
    try {
      const usuario = await Usuario.autenticar(datos.correo, datos.password);
      if (!usuario) {
        this.vista.mostrarMensaje("danger", "Correo o contraseña incorrectos.");
        this.vista.bloquearBoton(false);
        return;
      }
      this.vista.mostrarMensaje("success", `Bienvenido, ${usuario.nombre.split(" ")[0]}. Entrando a tu cuenta...`);
      setTimeout(() => this.vista.redirigir(sessionStorage.getItem('cinachReturn')==='compra.html'?'compra.html':'index.html'), 900);
    } catch (error) {
      this.vista.mostrarMensaje("danger", error.message);
      this.vista.bloquearBoton(false);
    }
  }
}
