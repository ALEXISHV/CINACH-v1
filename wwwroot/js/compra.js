const $ = (s) => document.querySelector(s);
const state = { marca:null, pelicula:null, sucursal:null, funcion:null, asientos:[], ticket:null, usuario:null };
// Solo respetar una selección directa desde la cartelera una vez por visita.
// Una selección guardada de compras anteriores no debe saltarse la pantalla Películas.
let peliculaPendiente = Number(new URLSearchParams(location.search).get('peliculaId')) || 0;
sessionStorage.removeItem('cinachMovie');
const panels = ["stepCine","stepPelicula","stepSucursal","stepFuncion","stepAsientos","stepPago","ticketResult"];
const esc = (v="") => String(v).replace(/[&<>"']/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
async function api(url, options={}) { const r=await fetch(url,{credentials:"same-origin",headers:{"Content-Type":"application/json",...(options.headers||{})},...options}); const d=await r.json().catch(()=>({})); if(!r.ok) throw new Error(d.mensaje || `Error ${r.status}`); return d; }
function aviso(texto,tipo="warning"){const a=$("#purchaseAlert");a.className=`alert alert-${tipo}`;a.textContent=texto;}
function ocultarAviso(){const a=$("#purchaseAlert");a.className="alert d-none";a.textContent="";}
function mostrar(p){panels.forEach(id=>$("#"+id).classList.toggle("d-none",id!==p)); const idx=panels.indexOf(p); document.querySelectorAll("#purchaseSteps span").forEach((x,i)=>x.classList.toggle("active",i<=Math.min(idx,5))); ocultarAviso(); window.scrollTo({top:0,behavior:"smooth"});}
async function iniciar(){
 try { const ses=await api("/api/auth/me"); state.usuario=ses.usuario; if(!state.usuario){ aviso("Para realizar una compra debes iniciar sesión.","info"); const a=document.createElement("a");a.href="login.html";sessionStorage.setItem("cinachReturn","compra.html");a.className="btn btn-cinach mt-2";a.textContent="Iniciar sesión";$("#purchaseAlert").append(" ",a); } }
 catch { aviso("No se pudo verificar tu sesión.","danger"); }
 document.querySelectorAll("[data-chain]").forEach(b=>b.addEventListener("click",()=>seleccionarCadena(b.dataset.chain)));
 document.querySelectorAll(".back-step").forEach(b=>b.addEventListener("click",()=>mostrar(panels[Number(b.dataset.back)])));
 $("#continuePayment").addEventListener("click",prepararPago);
 $("#paymentForm").addEventListener("submit",procesarPago);
 $("#downloadTicket").addEventListener("click",descargarTicket);
 $("#resendTicket").addEventListener("click",reenviarTicket);
}
async function seleccionarCadena(marca){
 if(!state.usuario){aviso("Inicia sesión antes de comprar.","info");return;}
 // Al cambiar de cadena se descartan selecciones dependientes de la anterior.
 state.marca=marca;
 state.pelicula=null;
 state.sucursal=null;
 state.funcion=null;
 state.asientos=[];
 // El enlace directo desde Cartelera se aplica una sola vez, nunca al cambiar de cine.
 const peliculaInicial = peliculaPendiente;
 peliculaPendiente = 0;
 try{
  const peliculas=await api(`/api/cadenas/${encodeURIComponent(marca)}/peliculas`);
  $("#moviesPurchase").innerHTML=peliculas.map(p=>`<div class="col-sm-6 col-lg-4"><button class="purchase-movie" data-id="${p.id}"><img src="${esc(p.poster)}" alt=""><span><b>${esc(p.titulo)}</b><small>${esc(p.clasificacion)} · ${p.duracion} min</small></span></button></div>`).join("")||'<p class="muted">No hay películas con funciones próximas.</p>';
  $("#moviesPurchase").querySelectorAll("button").forEach(b=>b.addEventListener("click",()=>seleccionarPelicula(Number(b.dataset.id),peliculas.find(p=>p.id===Number(b.dataset.id)))));
  mostrar("stepPelicula");
  const selected=peliculas.find(p=>p.id===peliculaInicial);
  if(selected)await seleccionarPelicula(selected.id,selected);
 }catch(e){aviso(e.message,"danger");}
}
async function seleccionarPelicula(id,p){state.pelicula=p;try{const suc=await api(`/api/cines?marca=${encodeURIComponent(state.marca)}`);$("#branchesPurchase").innerHTML=suc.map(x=>`<div class="col-md-6"><button class="branch-card" data-id="${x.id}"><b>${esc(x.sucursal)}</b><span>${esc(x.ciudad)}</span><small>${esc(x.direccion)}</small></button></div>`).join("");$("#branchesPurchase").querySelectorAll("button").forEach(b=>b.addEventListener("click",()=>seleccionarSucursal(suc.find(x=>x.id===Number(b.dataset.id)))));mostrar("stepSucursal");}catch(e){aviso(e.message,"danger");}}
async function seleccionarSucursal(s){state.sucursal=s;try{const funcs=await api(`/api/funciones?cineId=${s.id}&peliculaId=${state.pelicula.id}`);$("#showsPurchase").innerHTML=funcs.map(f=>`<div class="col-md-6 col-lg-4"><button class="show-card" data-id="${f.id}"><b>${new Date(f.fecha+"T12:00:00").toLocaleDateString("es-MX",{weekday:"long",day:"numeric",month:"long"})}</b><span>${f.hora} · ${esc(f.sala)}</span><small>$${Number(f.precio).toFixed(2)} MXN por boleto</small></button></div>`).join("")||'<p class="muted">No hay horarios para esta combinación.</p>';$("#showsPurchase").querySelectorAll("button").forEach(b=>b.addEventListener("click",()=>seleccionarFuncion(funcs.find(x=>x.id===Number(b.dataset.id)))));mostrar("stepFuncion");}catch(e){aviso(e.message,"danger");}}
async function seleccionarFuncion(f){state.funcion=f;state.asientos=[];try{const as=await api(`/api/funciones/${f.id}/asientos`);$("#seatMap").innerHTML=as.map(a=>`<button class="seat ${a.ocupado?"occupied":"free"}" ${a.ocupado?"disabled":""} data-id="${a.id}" data-seat="${a.fila}${a.numero}" aria-label="Asiento ${a.fila}${a.numero}">${a.fila}${a.numero}</button>`).join("");$("#seatMap").querySelectorAll(".seat.free").forEach(b=>b.addEventListener("click",()=>{const id=Number(b.dataset.id);if(state.asientos.includes(id)){state.asientos=state.asientos.filter(x=>x!==id);b.classList.remove("selected");}else if(state.asientos.length<8){state.asientos.push(id);b.classList.add("selected");}actualizarAsientos();}));actualizarAsientos();mostrar("stepAsientos");}catch(e){aviso(e.message,"danger");}}
function actualizarAsientos(){const labels=state.asientos.map(id=>$("#seatMap").querySelector(`[data-id="${id}"]`)?.dataset.seat).filter(Boolean);$("#seatSummary").textContent=labels.length?`Seleccionados: ${labels.join(", ")} · ${labels.length} boleto(s)`:"Ningún asiento seleccionado.";$("#continuePayment").disabled=!labels.length;}
function prepararPago(){const count=state.asientos.length;$("#orderDetails").innerHTML=`<p><b>${esc(state.pelicula.titulo)}</b></p><p>${esc(state.marca)} · ${esc(state.sucursal.sucursal)}</p><p>${state.funcion.fecha} · ${state.funcion.hora} · ${esc(state.funcion.sala)}</p><p>Asientos: ${state.asientos.map(id=>$("#seatMap").querySelector(`[data-id="${id}"]`)?.dataset.seat).join(", ")}</p><p>${count} × $${Number(state.funcion.precio).toFixed(2)}</p>`;$("#orderTotal").textContent=`$${(count*Number(state.funcion.precio)).toFixed(2)} MXN`;mostrar("stepPago");}
async function procesarPago(e){e.preventDefault();const btn=$("#payButton");btn.disabled=true;btn.textContent="Procesando...";try{const data=await api("/api/compras",{method:"POST",body:JSON.stringify({idCartelera:state.funcion.id,asientos:state.asientos,titular:$("#cardName").value,tarjetaPrueba:$("#testCard").value})});state.ticket=data.ticket;renderTicket(data);mostrar("ticketResult");}catch(err){aviso(err.message,"danger");btn.disabled=false;btn.textContent="Confirmar compra";}}
function renderTicket(data){const t=data.ticket||{};$("#ticketCard").innerHTML=`<div class="ticket-top"><strong>CINACH</strong><span>ENTRADA DE CINE</span></div><div class="ticket-body ticket-body-receipt"><h3>${esc(t.pelicula||state.pelicula.titulo)}</h3><p class="ticket-chain">${esc(t.cine||state.marca)} · ${esc(t.sucursal||state.sucursal.sucursal)}</p><div class="ticket-grid"><div><small>FECHA</small><b>${esc(String(t.fechaFuncion||state.funcion.fecha).slice(0,10))}</b></div><div><small>HORA</small><b>${esc(String(t.hora||state.funcion.hora).slice(0,5))}</b></div><div><small>SALA</small><b>${esc(t.sala||state.funcion.sala)}</b></div><div><small>ASIENTOS</small><b>${esc(t.asientos||"")}</b></div></div><div class="ticket-folio"><small>FOLIO</small><strong>${esc(t.folio||data.folio)}</strong></div><div class="ticket-qr-wrap"><div id="ticketQr"></div><small>Referencia de entrada</small></div><div class="ticket-total-row"><span>TOTAL</span><strong>$${Number(data.total||t.total||0).toFixed(2)} MXN</strong></div><p class="ticket-note">Comprobante académico de CINACH. Conserva tu folio para futuras consultas.</p></div>`;const qr=$("#ticketQr");if(qr && window.QRCode){qr.replaceChildren();new QRCode(qr,{text:`CINACH|${t.folio||data.folio}|CINACH-ACADEMICO`,width:112,height:112});}
$("#emailStatus").textContent= data.correoEnviado === true
  ? `Se envió el PDF a ${data.correo}. Revisa también Spam si no aparece.`
  : data.correoEnviado === false
    ? "La compra se guardó, pero el correo no se pudo enviar. Puedes descargar el PDF o reintentarlo más tarde."
    : "Puedes descargar el PDF o pedir su reenvío a tu correo registrado.";}
function obtenerFolioActual(){return String(state.ticket?.folio||"").trim();}
async function descargarTicket(){
 const folio=obtenerFolioActual();
 if(!folio){aviso("No se encontró el folio de la compra.","danger");return;}
 const boton=$("#downloadTicket");boton.disabled=true;
 try{
  const r=await fetch(`/api/tickets/${encodeURIComponent(folio)}/pdf`,{credentials:"same-origin",cache:"no-store"});
  if(!r.ok){const d=await r.json().catch(()=>({}));throw new Error(d.mensaje||"No se pudo descargar el PDF.");}
  const url=URL.createObjectURL(await r.blob());
  const a=document.createElement("a");a.href=url;a.download=`CINACH-${folio.replace(/[^a-zA-Z0-9-]/g,"")||"boleto"}.pdf`;
  document.body.appendChild(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(url),10000);
 }catch(e){aviso(e.message,"danger");}finally{boton.disabled=false;}
}
async function reenviarTicket(){
 const folio=obtenerFolioActual();if(!folio)return;
 const boton=$("#resendTicket");boton.disabled=true;boton.textContent="Enviando...";
 try{
  const data=await api(`/api/tickets/${encodeURIComponent(folio)}/reenviar`,{method:"POST"});
  $("#emailStatus").textContent=data.mensaje+" Revisa también la carpeta Spam.";
 }catch(e){$("#emailStatus").textContent=e.message;}finally{
  boton.disabled=false;boton.textContent="Reenviar a mi correo";
 }
}
const folio=new URLSearchParams(location.search).get('folio');
await iniciar();
if(folio && state.usuario){try{const t=await api(`/api/tickets/${encodeURIComponent(folio)}`);state.ticket=t;renderTicket({ticket:t,folio:t.folio,total:t.total});mostrar('ticketResult');}catch(e){aviso(e.message,'danger');}}
