import { Usuario } from '../models/Usuario.js?v=cinach-v2';

export class HomeController {
  iniciar() {
    const slides = [...document.querySelectorAll('.feature-slide[data-slide]')];
    const estado = document.getElementById('slideStatus');
    const anterior = document.getElementById('slidePrev');
    const siguiente = document.getElementById('slideNext');
    const alternar = document.getElementById('slideToggle');

    if (!slides.length || !estado || !anterior || !siguiente || !alternar) return;

    const movimientoReducido = window.matchMedia?.('(prefers-reduced-motion: reduce)').matches ?? false;
    let indice = 0;
    let pausado = movimientoReducido;
    let temporizador = null;
    const DURACION = 5500; // Milisegundos entre diapositivas.

    const renderizar = () => {
      slides.forEach((diapositiva, i) => {
        diapositiva.hidden = i !== indice;
      });
      estado.textContent = `${String(indice + 1).padStart(2, '0')} / ${String(slides.length).padStart(2, '0')}`;
    };

    const avanzar = (desplazamiento) => {
      indice = (indice + desplazamiento + slides.length) % slides.length;
      renderizar();
    };

    const detenerTemporizador = () => {
      if (temporizador !== null) {
        clearInterval(temporizador);
        temporizador = null;
      }
    };

    const programarTemporizador = () => {
      detenerTemporizador();
      if (!pausado && !document.hidden && slides.length > 1) {
        temporizador = setInterval(() => avanzar(1), DURACION);
      }
    };

    const actualizarBoton = () => {
      const accion = pausado ? 'Reanudar carrusel' : 'Pausar carrusel';
      alternar.textContent = pausado ? '▶' : 'Ⅱ';
      alternar.setAttribute('aria-label', accion);
      alternar.setAttribute('title', accion);
      alternar.setAttribute('aria-pressed', String(pausado));
    };

    anterior.addEventListener('click', () => {
      avanzar(-1);
      programarTemporizador();
    });
    siguiente.addEventListener('click', () => {
      avanzar(1);
      programarTemporizador();
    });
    alternar.addEventListener('click', () => {
      pausado = !pausado;
      actualizarBoton();
      programarTemporizador();
    });
    document.addEventListener('visibilitychange', programarTemporizador);

    renderizar();
    actualizarBoton();
    programarTemporizador();

    // La sesión se consulta sin bloquear la animación del carrusel.
    Usuario.sesionActual().then((usuario) => {
      const promociones = document.getElementById('promociones');
      if (usuario && promociones) promociones.hidden = true;
    }).catch(() => {});
  }
}
