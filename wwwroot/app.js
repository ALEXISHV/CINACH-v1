// PUNTO DE ENTRADA: cada página indica con data-pagina qué controlador debe arrancar.
import { NavegacionController } from "./controllers/NavegacionController.js?v=cinach-v2";
import { HomeController } from "./controllers/HomeController.js?v=cinach-v2-hero-fix-1105";
import { CarteleraController } from "./controllers/CarteleraController.js?v=cinach-v2";
import { AuthController } from "./controllers/AuthController.js?v=cinach-v2";

document.addEventListener("DOMContentLoaded", () => {
  new NavegacionController().iniciar();

  const pagina = document.body.dataset.pagina;
  if (pagina === "inicio") new HomeController().iniciar();
  else if (pagina === "cartelera") new CarteleraController().iniciar();
  else if (pagina === "registro" || pagina === "login") new AuthController(pagina).iniciar();
});
