// VISTA: zona de acceso de la barra de navegación (iniciar sesión / registrarse o saludo y cerrar sesión).
export class NavbarView {
  constructor() {
    this.contenedor = document.getElementById("navAuth");
  }

  mostrar(usuario) {
    if (!this.contenedor) return;
    this.contenedor.replaceChildren();

    if (usuario) {
      const saludo = document.createElement("span");
      saludo.className = "nav-user";
      saludo.textContent = `Hola, ${usuario.nombre.split(" ")[0]}`;

      const boton = document.createElement("button");
      boton.type = "button";
      boton.id = "btnCerrarSesion";
      boton.className = "btn btn-outline-light btn-sm";
      boton.textContent = "Cerrar sesión";

      if (usuario.rol === "admin") {
        const admin = document.createElement("a");
        admin.href = "admin.html";
        admin.className = "btn btn-cinach btn-sm";
        admin.textContent = "Administración";
        this.contenedor.append(admin);
      }
      const history=document.createElement('a');history.href='mis-compras.html';history.className='btn btn-outline-light btn-sm';history.textContent='Mis compras';
      this.contenedor.append(history,saludo, boton);
      return;
    }

    const login = document.createElement("a");
    login.href = "login.html";
    login.className = "btn btn-outline-light btn-sm";
    login.textContent = "Iniciar sesión";

    const registro = document.createElement("a");
    registro.href = "registro.html";
    registro.className = "btn btn-cinach btn-sm";
    registro.textContent = "Registrarse";

    this.contenedor.append(login, registro);
  }

  alCerrarSesion(manejador) {
    const boton = document.getElementById("btnCerrarSesion");
    if (boton) boton.addEventListener("click", manejador);
  }

  irA(url) {
    window.location.href = url;
  }
}
