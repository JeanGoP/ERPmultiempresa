const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
class Node{constructor(tag){this.tag=tag;this.children=[];this.events={};this.value='';this.checked=false;this.isConnected=true;}append(...items){this.children.push(...items);}setAttribute(){}addEventListener(name,fn){this.events[name]=fn;}}
let token='one',calls=[],reply;
const context=vm.createContext({document:{createElement:t=>new Node(t),createTextNode:t=>t},state:{erpSession:{superAdmin:true}},apiToken:()=>token,apiRequest:(path,options)=>{calls.push({path,options});return new Promise(r=>reply=r);}});
vm.runInContext(fs.readFileSync('public/company-zeus.js','utf8'),context);
function fields(record){const form=new Node('form'),helper=context.companyZeusFields(form,record,token),section=form.children[0],enable=section.children[1].children[0],grid=section.children[2],inputs=grid.children.slice(0,5).map(x=>x.children[1]);return {helper,section,enable,inputs,test:section.children[3]};}
(async()=>{
  const fresh=fields(null);assert.equal(fresh.helper.read(),null);
  fresh.enable.checked=true;fresh.enable.onchange();['sql-server','ZEUS_TEST','login-sql','secret-not-persisted','usuario-contable'].forEach((v,i)=>fresh.inputs[i].value=v);
  const payload=fresh.helper.read();assert.equal(payload.usuarioSql,'login-sql');assert.equal(payload.usuarioContable,'usuario-contable');assert.equal(payload.password,'secret-not-persisted');
  const pending=fresh.test.onclick();assert.match(calls[0].path,/\/0\/zeus-connection\/test$/);reply({contratoDisponible:true,baseDatos:'ZEUS_TEST'});await pending;
  fresh.helper.clear();assert.equal(fresh.inputs[3].value,'');
  const edit=fields({id:3});reply({servidor:'host',baseDatos:'base',usuarioSql:'sql',usuarioContable:'contable',tienePassword:true,version:2,versionConfiguracion:7,origen:'MAESTRO'});await Promise.resolve();
  assert.equal(edit.inputs[3].value,'');assert.equal(edit.helper.read(),null);
  edit.inputs[4].value='nuevo';edit.section.events.input();const changed=edit.helper.read();assert.equal(changed.password,null);assert.equal(changed.version,2);assert.equal(changed.versionConfiguracion,7);
  const stale=fields({id:4});token='two';reply({servidor:'DO_NOT_SHOW',origen:'MAESTRO'});await Promise.resolve();assert.equal(stale.inputs[0].value,'');
  const ui=fs.readFileSync('public/zeus.js','utf8');assert.doesNotMatch(ui,/zeusField\('Servidor SQL'|zeusField\('Base contable de Zeus'|zeusField\('Usuario de Zeus'/);
  console.log('Conexión Zeus UI: opcional, usuarios separados, contraseña no recuperada, versiones, prueba sin guardar y respuestas obsoletas verificadas.');
})().catch(e=>{console.error(e);process.exitCode=1;});
