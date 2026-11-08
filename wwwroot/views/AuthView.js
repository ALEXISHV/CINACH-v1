// VISTA: formularios de registro e inicio de sesión.
export class AuthView {
  constructor(idFormulario) {
    this.formulario = document.getElementById(idFormulario);
    this.boton = this.formulario.querySelector("button[type='submit']");
    this.mensaje = document.getElementById("mensajeFormulario");
  }

  obtenerDatos() {
    const datos = {};
    new FormData(this.formulario).forEach((valor, clave) => { datos[clave] = valor; });
    datos.terminos = this.formulario.elements.terminos ? this.formulario.elements.terminos.checked : true;
    return datos;
  }

  limpiar() {
    this.formulario.querySelectorAll(".is-invalid").forEach((campo) => campo.classList.remove("is-invalid"));
    this.mensaje.className = "d-none";
    this.mensaje.textContent = "";
  }

  mostrarErrores(errores) {
    Object.entries(errores).forEach(([campo, texto]) => {
      const entrada = this.formulario.elements[campo];
      const aviso = document.getElementById(`error-${campo}`);
      if (entrada) entrada.classList.add("is-invalid");
      if (aviso) aviso.textContent = texto;
    });
    const primero = this.formulario.querySelector(".is-invalid");
    if (primero) primero.focus();
  }

  mostrarMensaje(tipo, texto) {
    this.mensaje.className = `alert alert-${tipo}`;
    this.mensaje.textContent = texto;
  }

  bloquearBoton(bloqueado) {
    this.boton.disabled = bloqueado;
  }

  redirigir(url) {
    window.location.href = url;
  }

  alEnviar(manejador) {
    this.formulario.addEventListener("submit", (evento) => {
      evento.preventDefault();
      manejador();
    });
  }
}
