// VISTA
export class PeliculaView {
  constructor() {
    this.contenedor = document.getElementById("contenedorPeliculas");
    this.filtro = document.getElementById("filtroGenero");
    this.toastElemento = document.getElementById("cinachToast");
    this.toastMensaje = document.getElementById("toastMensaje");
    this.manejadorVerFunciones = null;
  }

  //Renderizado

  mostrarPeliculas(peliculas) {
    if (peliculas.length === 0) {
      this.contenedor.innerHTML = `
        <div class="col-12">
          <div class="alert alert-secondary" role="status">No hay películas para el género seleccionado.</div>
        </div>`;
      return;
    }

    this.contenedor.innerHTML = peliculas.map((pelicula) => this.crearTarjeta(pelicula)).join("");

    // Si falta un archivo local, mostrar el título en lugar de una imagen rota.
    this.contenedor.querySelectorAll(".movie-poster img").forEach((imagen) => {
      const mostrarTexto = () => {
        const tarjeta = imagen.closest(".movie-poster");
        if (!tarjeta) return;
        tarjeta.classList.remove("has-image");
        const numero = document.createElement("span");
        numero.className = "poster-number";
        numero.textContent = imagen.dataset.numero;
        const titulo = document.createElement("div");
        titulo.className = "poster-title";
        titulo.textContent = imagen.dataset.titulo;
        imagen.replaceWith(numero, titulo);
      };
      imagen.addEventListener("error", mostrarTexto, { once: true });
      // También atiende imágenes que hayan fallado antes de registrar el evento.
      if (imagen.complete && imagen.naturalWidth === 0) mostrarTexto();
    });

    this.contenedor.querySelectorAll(".btn-funciones").forEach((boton) => {
      boton.addEventListener("click", () => {
        if (this.manejadorVerFunciones) this.manejadorVerFunciones(Number(boton.dataset.id));
      });
    });
  }

  crearTarjeta(pelicula) {
    const escape=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
    const raw=pelicula.imagen||pelicula.respaldo||'';
    pelicula=Object.fromEntries(Object.entries(pelicula).map(([k,v])=>[k,escape(v)]));
    const imagen = /^img\/posters\/[A-Za-z0-9_-]+\.(jpg|jpeg|png|webp)$/.test(raw)?escape(raw):'';
    const poster = imagen
      ? `<img src="${imagen}" data-numero="${pelicula.numero}" data-titulo="${pelicula.titulo}" data-id="${pelicula.id}" alt="Póster de ${pelicula.titulo}" loading="lazy">`
      : `<span class="poster-number">${pelicula.numero}</span>
         <div class="poster-title">${pelicula.titulo}</div>`;

    return `
      <div class="col-sm-6 col-lg-4 col-xl-3">
        <article class="movie-card">
          <div class="movie-poster ${imagen ? "has-image" : ""}" style="--poster-a: ${pelicula.colorA}; --poster-b: ${pelicula.colorB};">
            ${poster}
          </div>
          <div class="movie-info">
            <div class="d-flex justify-content-between align-items-center gap-2 mb-2">
              <span class="badge genre-badge">${pelicula.genero}</span>
              <span class="movie-meta">${pelicula.clasificacion}</span>
            </div>
            <h3>${pelicula.titulo}</h3>
            <p class="movie-meta mb-2">${pelicula.duracion}</p>
            <p class="muted small">${pelicula.descripcion}</p>
            <button class="btn btn-outline-gold w-100 btn-funciones" data-titulo="${pelicula.titulo}" data-id="${pelicula.id}">
              Ver funciones
            </button>
          </div>
        </article>
      </div>`;
  }

  mostrarError(texto) {
    this.contenedor.innerHTML = '<div class="col-12"><div class="alert alert-warning" role="alert"></div></div>';
    this.contenedor.querySelector(".alert").textContent = texto;
  }

  // Llena el filtro con los géneros que existen en la base de datos.
  cargarGeneros(lista) {
    if (!this.filtro || lista.length === 0) return;
    this.filtro.replaceChildren(new Option("Todos los géneros", "Todas"), ...lista.map((g) => new Option(g, g)));
  }

  mostrarAviso(mensaje) {
    this.toastMensaje.textContent = mensaje;
    bootstrap.Toast.getOrCreateInstance(this.toastElemento).show();
  }

  obtenerGeneroSeleccionado() {
    return this.filtro ? this.filtro.value : "Todas";
  }

  //Eventos

  alCambiarGenero(manejador) {
    if (this.filtro) this.filtro.addEventListener("change", manejador);
  }

  alVerFunciones(manejador) {
    this.manejadorVerFunciones = manejador;
  }

  alHacerClic(idElemento, manejador) {
    const elemento = document.getElementById(idElemento);
    if (elemento) elemento.addEventListener("click", manejador);
  }
}
