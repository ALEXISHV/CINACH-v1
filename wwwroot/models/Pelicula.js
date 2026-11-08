// MODELO: catálogo de películas. Los datos vienen de SQL Server a través de la API (sp_ListarPeliculas).
const PALETAS = [["#1b4965", "#5fa8d3"], ["#003049", "#d62828"], ["#264653", "#2a9d8f"], ["#5a189a", "#c77dff"]];

export class Pelicula {
  constructor(fila, indice) {
    const [colorA, colorB] = PALETAS[indice % PALETAS.length];
    this.id = fila.id_pelicula;
    this.titulo = fila.titulo;
    this.genero = fila.genero;
    this.duracion = Pelicula.formatoDuracion(fila.duracion_minutos);
    this.clasificacion = fila.clasificacion;
    this.descripcion = fila.sinopsis || "";
    this.colorA = colorA;
    this.colorB = colorB;
    this.numero = String(indice + 1).padStart(2, "0");
    this.imagen = fila.poster_url || "";
    this.respaldo = this.imagen;
  }

  static formatoDuracion(minutos) {
    const h = Math.floor(minutos / 60);
    const m = String(minutos % 60).padStart(2, "0");
    return h > 0 ? `${h} h ${m} min` : `${minutos} min`;
  }

  static async obtenerTodas() {
    const resp = await fetch("api/peliculas");
    if (!resp.ok) throw new Error("No se pudo cargar la cartelera. Inténtalo más tarde.");
    return (await resp.json()).map((fila, i) => new Pelicula(fila, i));
  }

  static async obtenerGeneros() {
    const resp = await fetch("api/generos");
    return resp.ok ? resp.json() : [];
  }
}
