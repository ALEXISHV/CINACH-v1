// CONTROLADOR de la cartelera: catálogo completo de películas con filtro por género.
import { Pelicula } from "../models/Pelicula.js?v=cinach-v2";
import { PeliculaView } from "../views/PeliculaView.js?v=cinach-v2";

export class CarteleraController {
  constructor() {
    this.peliculas = [];
    this.vista = new PeliculaView();
  }

  async iniciar() {
    this.configurarEventos();
    try {
      this.vista.cargarGeneros(await Pelicula.obtenerGeneros());
      this.peliculas = await Pelicula.obtenerTodas();
      this.vista.mostrarPeliculas(this.peliculas);
    } catch (error) {
      this.vista.mostrarError(error.message);
    }

  }

  configurarEventos() {
    this.vista.alCambiarGenero(() => this.filtrarPeliculas());

    this.vista.alVerFunciones((peliculaId) => {
      window.location.href = `compra.html?peliculaId=${encodeURIComponent(peliculaId)}`;
    });
  }

  filtrarPeliculas() {
    const genero = this.vista.obtenerGeneroSeleccionado();
    const resultado = genero === "Todas"
      ? this.peliculas
      : this.peliculas.filter((pelicula) => pelicula.genero === genero);
    this.vista.mostrarPeliculas(resultado);
  }
}
