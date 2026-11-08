// MODELO: usuarios y sesión. Habla con la API (/api/auth/*), que guarda todo en SQL Server.
const REGEX_CORREO = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

async function api(url, opciones = {}) {
  let resp;
  try {
    resp = await fetch(url, { credentials: "same-origin", headers: { "Content-Type": "application/json" }, ...opciones });
  } catch (error) {
    throw new Error("No se pudo conectar con el servidor. Inténtalo más tarde.");
  }
  const datos = await resp.json().catch(() => ({}));
  if (!resp.ok) {
    const error = new Error(datos.mensaje || "Ocurrió un error. Inténtalo de nuevo.");
    error.estado = resp.status;
    throw error;
  }
  return datos;
}

export class Usuario {
  static validarRegistro({ nombre, correo, password, confirmacion, terminos }) {
    const errores = {};
    if (!nombre || nombre.trim().length < 3) errores.nombre = "Escribe tu nombre completo (mínimo 3 caracteres).";
    if (!REGEX_CORREO.test((correo || "").trim())) errores.correo = "Escribe un correo válido, por ejemplo nombre@unach.mx.";
    if (!password || password.length < 8 || !/[A-Za-z]/.test(password) || !/\d/.test(password)) {
      errores.password = "La contraseña debe tener mínimo 8 caracteres, con letras y números.";
    }
    if (confirmacion !== password) errores.confirmacion = "Las contraseñas no coinciden.";
    if (!terminos) errores.terminos = "Debes aceptar los términos para continuar.";
    return errores;
  }

  static validarLogin({ correo, password }) {
    const errores = {};
    if (!REGEX_CORREO.test((correo || "").trim())) errores.correo = "Escribe un correo válido.";
    if (!password) errores.password = "Escribe tu contraseña.";
    return errores;
  }

  static async registrar({ nombre, correo, password }) {
    await api("api/auth/registro", { method: "POST", body: JSON.stringify({ nombre, correo, password }) });
  }

  // Devuelve el usuario si los datos son correctos (el servidor abre la sesión) o null si no lo son.
  static async autenticar(correo, password) {
    try {
      const datos = await api("api/auth/login", { method: "POST", body: JSON.stringify({ correo, password }) });
      return datos.usuario;
    } catch (error) {
      if (error.estado === 401) return null;
      throw error;
    }
  }

  static async sesionActual() {
    try {
      return (await api("api/auth/me")).usuario;
    } catch (error) {
      return null;
    }
  }

  static async cerrarSesion() {
    try { await api("api/auth/logout", { method: "POST" }); } catch (error) { /* sin sesión que cerrar */ }
  }
}
