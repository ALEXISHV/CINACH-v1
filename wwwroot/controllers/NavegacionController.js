// CONTROLADOR: barra de navegación. Muestra el acceso según haya o no una sesión iniciada.
import { Usuario } from "../models/Usuario.js?v=cinach-v2";
import { NavbarView } from "../views/NavbarView.js?v=cinach-v2";

export class NavegacionController {
  constructor() {
    this.vista = new NavbarView();
  }

  async iniciar() {
    const usuario = await Usuario.sesionActual();
    this.vista.mostrar(usuario);

    // No dejar un enlace a Promociones si la sección está oculta.
    if (usuario) {
      document.querySelectorAll('a[href="index.html#promociones"]').forEach((enlace) => {
        enlace.closest(".nav-item")?.classList.add("d-none");
      });
    }
    this.vista.alCerrarSesion(async () => {
      await Usuario.cerrarSesion();
      this.vista.irA("index.html");
    });
  }
}
