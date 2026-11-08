const $=id=>document.getElementById(id), esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
let tab='estadisticas',rows=[],lookup={},editId=0,me;
function alert(text,type='danger'){$('adminAlert').className=`alert alert-${type}`;$('adminAlert').textContent=text;}
async function api(url,options={}){const r=await fetch(url,{credentials:'same-origin',...options,headers:{'Content-Type':'application/json',...options.headers}});const d=await r.json().catch(()=>({}));if(!r.ok)throw new Error(d.mensaje||(r.status===403?'No tienes permisos de administración.':r.status===401?'Tu sesión terminó. Inicia sesión de nuevo.':'No se pudo completar la solicitud.'));return d;}
const field=(name,label,value='',type='text',extra='')=>`<div class="col-md-6"><label for="f-${name}">${label}</label><input id="f-${name}" name="${name}" type="${type}" value="${esc(value)}" class="form-control" ${extra}></div>`;
function select(name,label,options,value){return `<div class="col-md-6"><label for="f-${name}">${label}</label><select name="${name}" id="f-${name}" class="form-select" required><option value="">Seleccionar…</option>${options.map(o=>`<option value="${esc(o.id)}" ${String(o.id)===String(value)?'selected':''}>${esc(o.nombre)}</option>`).join('')}</select></div>`;}
function esFuncTab(){return tab==='funciones'||tab==='historial';}
async function load(){
 $('editor').hidden=true;
 $('dashboard').hidden=tab!=='estadisticas';
 $('catalog').hidden=tab==='estadisticas';
 if(tab==='estadisticas'){await stats();return;}
 $('catalogTitle').textContent={peliculas:'Películas',usuarios:'Usuarios',funciones:'Funciones próximas y en curso',historial:'Historial de funciones'}[tab];
 $('add').hidden=tab==='historial';
 $('rows').innerHTML='<tr><td>Cargando…</td></tr>';
 [rows,lookup]=await Promise.all([api(`/api/admin/${esFuncTab()?'funciones':tab}`),api('/api/admin/catalogos')]);
 render();
}
function render(){
 if(tab==='estadisticas')return;
 const q=$('search').value.toLocaleLowerCase();
 let visible=rows;
 if(tab==='funciones')visible=rows.filter(x=>x.estado==='Próxima'||x.estado==='En curso');
 if(tab==='historial')visible=rows.filter(x=>x.estado==='Finalizada'||x.estado==='Inactiva');
 const filtered=visible.filter(x=>Object.values(x).some(v=>String(v).toLocaleLowerCase().includes(q)));
 const titles={peliculas:['Película','Duración','Clasificación','Estado'],usuarios:['Nombre','Correo','Rol','Estado'],funciones:['Película / Sucursal','Fecha / Hora','Sala / Precio','Boletos / Estado'],historial:['Película / Sucursal','Fecha / Hora','Sala / Precio','Boletos / Estado']}[tab];
 $('thead').innerHTML=`<tr>${titles.map(t=>`<th>${t}</th>`).join('')}<th>Acciones</th></tr>`;
 $('rows').innerHTML=filtered.map(x=>{
  const status=x.activo?'Activo':'Inactivo';
  let cells, actions;
  if(tab==='peliculas'){
   cells=[esc(x.titulo),`${x.duracion} min`,esc(x.clasificacion),status];
  }else if(tab==='usuarios'){
   cells=[esc(x.nombre),esc(x.correo),esc(x.rol),status];
  }else{
   const statusText=x.estado||status;
   const badgeClass={'Próxima':'text-bg-success','En curso':'text-bg-warning','Finalizada':'text-bg-secondary','Inactiva':'text-bg-dark'}[statusText]||'text-bg-secondary';
   cells=[`${esc(x.pelicula)}<br><small>${esc(x.sucursal)}</small>`,
      `${esc(x.fecha)}<br>${esc(x.hora)} – ${esc(x.horaFin)}`,
      `${esc(x.sala)}<br>$${Number(x.precio).toFixed(2)}`,
      `${Number(x.boletosVendidos)} boletos<br><span class="badge ${badgeClass}">${esc(statusText)}</span>`];
  }
  if(esFuncTab()){
   // Una función con tickets o comenzada no se edita: se programa otra sin cambiar el ticket anterior.
   if(x.estado==='Próxima' && Number(x.ticketsEmitidos)===0){
    actions=`<button class="btn btn-sm btn-outline-light" data-edit="${x.id}">Editar</button>`+
     (x.activo?`<button class="btn btn-sm btn-outline-danger" data-delete="${x.id}">Dar de baja</button>`:'');
   }else{
    actions=`<button class="btn btn-sm btn-cinach" data-reprogram="${x.id}">Reprogramar</button>`;
   }
  }else{
   actions=`<button class="btn btn-sm btn-outline-light" data-edit="${x.id}">Editar</button>`+
      (x.activo?`<button class="btn btn-sm btn-outline-danger" data-delete="${x.id}">Dar de baja</button>`:'');
  }
  return `<tr>${cells.map(c=>`<td>${c}</td>`).join('')}<td><div class="d-flex flex-wrap gap-2">${actions}</div></td></tr>`;
 }).join('')||'<tr><td colspan="5">No hay funciones en este estado ni registros que coincidan con tu búsqueda.</td></tr>';
 $('count').textContent=`${filtered.length} de ${visible.length} registros`;
 $('rows').querySelectorAll('[data-edit]').forEach(b=>b.onclick=()=>editor(rows.find(x=>x.id===Number(b.dataset.edit))));
 $('rows').querySelectorAll('[data-reprogram]').forEach(b=>b.onclick=()=>{
  const x=rows.find(y=>y.id===Number(b.dataset.reprogram));
  if(!x)return;
  // Copiar referencias pero dejar fecha y hora vacías para evitar usar la fecha antigua.
  tab='funciones';
  document.querySelectorAll('[data-tab]').forEach(el=>el.classList.toggle('active',el.dataset.tab===tab));
  render();
  $('catalogTitle').textContent='Reprogramar función';$('add').hidden=false;
  editor({...x,id:0,fecha:'',hora:'',activo:true},true);
 });
 $('rows').querySelectorAll('[data-delete]').forEach(b=>b.onclick=async()=>{
  if(!confirm('¿Dar de baja este registro? Se conservará su historial.'))return;
  b.disabled=true;
  try{const d=await api(`/api/admin/${esFuncTab()?'funciones':tab}/${b.dataset.delete}`,{method:'DELETE'});await load();alert(d.mensaje,'success');}
  catch(e){alert(e.message);b.disabled=false;}
 });
}
function editor(x={},reprogramar=false){
 editId=reprogramar?0:(x.id||0);
 let content='';
 if(tab==='peliculas')content=field('titulo','Título',x.titulo,'text','required maxlength="100"')+field('duracion','Duración (minutos)',x.duracion||120,'number','required min="1" max="600"')+select('clasificacion','Clasificación',['AA','A','B','B15','C','D'].map(id=>({id,nombre:id})),x.clasificacion||'B')+select('categoria','Categoría',lookup.categorias,x.categoria)+field('poster','Póster: ruta local (opcional)',x.poster||'','text','maxlength="200" placeholder="img/posters/coco.jpg"')+`<div class="col-12"><label for="f-sinopsis">Sinopsis</label><textarea class="form-control" id="f-sinopsis" name="sinopsis" maxlength="5000" rows="3">${esc(x.sinopsis)}</textarea></div>`;
 if(tab==='usuarios')content=field('nombre','Nombre',x.nombre,'text','required minlength="3" maxlength="100"')+field('correo','Correo',x.correo,'email','required maxlength="100"')+select('rol','Rol',['estudiante','docente','admin'].map(id=>({id,nombre:id})),x.rol||'estudiante')+(editId?'':field('password','Contraseña inicial (letras y números)','','password','required minlength="8" maxlength="128" autocomplete="new-password"'));
 if(esFuncTab())content=select('peliculaId','Película',lookup.peliculas,x.peliculaId)+select('salaId','Sucursal / Sala',lookup.salas,x.salaId)+select('precioId','Precio del boleto',lookup.precios,x.precioId)+field('fecha','Nueva fecha (Tuxtla)',reprogramar?'':(x.fecha||''),'date','required')+field('horaInicio','Nueva hora de inicio',reprogramar?'':(x.hora||''),'time','required')+
  `<p class="notice">${reprogramar?'Se creará una función nueva. La función anterior, sus tickets y sus ventas permanecerán en el historial.':'El final se calcula con la duración de la película. Se requieren 20 minutos de limpieza entre funciones. Una función iniciada o vendida no puede editarse.'}</p>`;
 const label=reprogramar?'Reprogramar película':editId?'Editar registro':'Crear registro';
 $('editor').innerHTML=`<h3 class="h5">${label}</h3><div class="row g-3">${content}<div class="col-12"><label><input type="checkbox" name="activo" ${reprogramar||x.activo!==false?'checked':''}> Activo</label></div></div><div class="d-flex gap-2 mt-3"><button class="btn btn-cinach" type="submit">${reprogramar?'Crear nueva función':'Guardar'}</button><button id="cancelEdit" class="btn btn-outline-light" type="button">Cancelar</button></div>`;
 $('editor').hidden=false;
 $('cancelEdit').onclick=()=>$('editor').hidden=true;
 $('editor').scrollIntoView({behavior:'smooth',block:'center'});
}
$('editor').onsubmit=async e=>{
 e.preventDefault();
 const body=Object.fromEntries(new FormData(e.currentTarget));
 body.activo=e.currentTarget.elements.activo.checked;
 for(const k of ['duracion','categoria','peliculaId','salaId','precioId'])if(k in body)body[k]=Number(body[k]);
 const btn=e.currentTarget.querySelector('[type=submit]');btn.disabled=true;
 try{
  const d=await api(`/api/admin/${esFuncTab()?'funciones':tab}${editId?'/'+editId:''}`,{method:editId?'PUT':'POST',body:JSON.stringify(body)});
  await load();alert(d.mensaje,'success');
 }catch(err){alert(err.message);}finally{btn.disabled=false;}
};
async function stats(){const d=await api(`/api/admin/estadisticas?desde=${$('from').value}&hasta=${$('to').value}`);$('reportDates').textContent=`Periodo: ${$('from').value} a ${$('to').value}`;$('metrics').innerHTML=[['Ingresos registrados',`$${Number(d.ingresos).toLocaleString('es-MX',{minimumFractionDigits:2,maximumFractionDigits:2})}`],['Compras',d.compras],['Boletos',d.boletos]].map(([label,value])=>`<div class="admin-card metric"><span>${label}</span><strong>${value}</strong></div>`).join('');const max=Math.max(1,...d.peliculas.map(p=>Number(p.ingresos)));$('ranking').innerHTML=d.peliculas.map(p=>`<div class="mb-4"><div class="d-flex justify-content-between gap-3"><b>${esc(p.pelicula)}</b><span>${p.boletos} boletos · ${p.compras} compras · $${Number(p.ingresos).toFixed(2)}</span></div><div class="bar-track"><span style="width:${Math.max(1,Number(p.ingresos)/max*100)}%"></span></div></div>`).join('')||'<p class="muted">No hay compras en este periodo.</p>';}
$('search').oninput=render;$('add').onclick=()=>editor();$('statsFilter').onsubmit=async e=>{e.preventDefault();try{await stats();}catch(err){alert(err.message);}};$('printReport').onclick=()=>window.print();
document.querySelectorAll('[data-tab]').forEach(b=>b.onclick=async()=>{tab=b.dataset.tab;$('search').value='';document.querySelectorAll('[data-tab]').forEach(x=>x.classList.toggle('active',x===b));try{await load();}catch(e){alert(e.message);}});
const today=new Intl.DateTimeFormat('en-CA',{timeZone:'America/Mexico_City',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());$('to').value=today;$('from').value=today.slice(0,7)+'-01';
try{me=(await api('/api/auth/me')).usuario;if(!me){location.href='login.html';}else if(me.rol!=='admin'){document.querySelector('main').innerHTML='<div class="alert alert-danger">No tienes permisos de administración.</div><a href="index.html">Volver al inicio</a>';}else await load();}catch(e){alert(e.message);}

// Actualización automática de los estados mientras el administrador mantiene abierto el panel.
setInterval(()=>{if(esFuncTab() && $('editor').hidden){load().catch(e=>alert(e.message));}},60000);
