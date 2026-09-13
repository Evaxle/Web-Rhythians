import { validateSspm } from './sspm.mjs';
const BASE = 'https://www.rhythians.com';
const $ = id => document.getElementById(id);
const db = await new Promise((resolve,reject) => {
  const r = indexedDB.open('RhythiansBrowser',2);
  r.onupgradeneeded = () => { for (const name of ['account','maps','scores','settings','mapmeta']) if(!r.result.objectStoreNames.contains(name)) r.result.createObjectStore(name); };
  r.onsuccess = () => resolve(r.result); r.onerror = () => reject(r.error);
  r.onblocked = () => reject(new Error('Close other Rhythians tabs to update browser storage.'));
}).catch(error=>{ $('status').textContent='Browser storage could not open: '+error.message;throw error; });
function storage(store,method,key,value) {
  return new Promise((resolve,reject) => {
    const tx = db.transaction(store,method === 'get' || method === 'getAll' || method === 'getKey' ? 'readonly' : 'readwrite');
    const object = tx.objectStore(store); const r = method === 'put' ? object.put(value,key) : method === 'getAll' ? object.getAll() : object[method](key);
    tx.oncomplete = () => resolve(r.result); tx.onerror = tx.onabort = () => reject(tx.error || r.error);
  });
}
let account = await storage('account','get','current');
let offset = 0, hasMore = false, generation = 0, downloadBusy = false, loginGeneration = 0;
let profileCache;
let engineReady, engineStarted = false, activeAccount, menuWait, resolveMenu;
let spin = Boolean(await storage('settings','get','spin'));
$('spin').checked = spin;
function notice(message) { $('status').textContent = message; }
function node(tag,text,className) { const n = document.createElement(tag); if(text != null)n.textContent=text;if(className)n.className=className;return n; }
function safeUrl(value) { try {const u=new URL(value,BASE);return ['https:','http:'].includes(u.protocol) ? u.href : ''; } catch{return '';} }
function picture(url,alt,className='cover') {const img=node('img',null,className);img.alt=alt;img.loading='lazy';img.decoding='async';img.src=safeUrl(url)||'logo.png';img.onerror=()=>{img.onerror=null;img.src='logo.png';};return img;}
async function api(path,body,auth=account) {
  const response=await fetch(BASE+path,{method:body === undefined ? 'GET':'POST',headers:{...(body === undefined ? {}:{'Content-Type':'application/json'}),...(auth?.token ? {Authorization:'Bearer '+auth.token}:{})},...(body === undefined ? {}:{body:JSON.stringify(body)}),credentials:'omit',signal:AbortSignal.timeout(45000)});
  const data=await response.json().catch(()=>({error:'Invalid server response.'}));
  if(!response.ok || data.ok === false) {const error=new Error(data.error||`Request failed (${response.status}).`);error.status=response.status;throw error;}return data;
}
function accountButton(){ $('account').textContent=account ? `${account.username} · Sign out`:'Sign in'; }
accountButton();
$('account').onclick=async()=>{
  if(account){account=null;await storage('account','delete','current');accountButton();await render();return;}
  const attempt=++loginGeneration;$('login').showModal();$('code').textContent='…';$('authorize').removeAttribute('href');$('login-status').textContent='Requesting a code…';
  try {
    const data=await api('/api/rhythkit/device/start',{},null);if(attempt!==loginGeneration)return;
    const verification=new URL(data.verificationUrl);if(verification.origin!==BASE)throw new Error('Unexpected authorization website.');
    $('code').textContent=data.userCode;$('authorize').href=verification.href;$('login-status').textContent='Waiting for approval. Passwords are entered only on Rhythians.';
    const expiry=Date.now()+data.expiresIn*1000;
    while(attempt===loginGeneration && Date.now()<expiry){
      await new Promise(r=>setTimeout(r,5000));if(attempt!==loginGeneration)return;
      const result=await api('/api/rhythkit/device/poll',{deviceCode:data.deviceCode},null);
      if(attempt!==loginGeneration)return;
      if(result.authorized && result.token){account={token:result.token,userId:result.userId,username:result.username,installationId:result.installationId};await storage('account','put','current',account);$('login').close();accountButton();await render();flushScores();return;}
    }
    if(attempt===loginGeneration)$('login-status').textContent='Code expired. Close this window and try again.';
  }catch(error){$('login-status').textContent=error.message;}
};
$('cancel-login').onclick=()=>{$('login').close();};$('login').onclose=()=>{loginGeneration++;};
$('spin').onchange=async()=>{spin=$('spin').checked;await storage('settings','put','spin',spin);if(window.rhythiansCommand)window.rhythiansCommand(JSON.stringify({action:'spin',enabled:spin}));};
window.rhythiansReady=text=>{const state=JSON.parse(text);if(!state.persistent)notice('Persistent game storage is unavailable; browser data may be temporary.');else window.rhythiansPersistUserData?.().catch(()=>{});engineReady?.resolve();resolveMenu?.();resolveMenu=undefined;};
window.rhythiansMode=async enabled=>{spin=Boolean(enabled);$('spin').checked=spin;await storage('settings','put','spin',spin);};
window.rhythiansError=message=>{$('game-status').textContent=message;};
window.rhythiansSelected=()=>{$('game-status').textContent='Choose modifiers and press Play in the game.';};
window.rhythiansScore=async text=>{
  if(!activeAccount)return;
  const score={...JSON.parse(text),clientScoreId:crypto.randomUUID(),completedAt:new Date().toISOString()};
  await storage('scores','put',score.clientScoreId,{score,userId:activeAccount.userId});
  $('game-status').textContent='Pass saved. Submitting to Rhythians…';await flushScores();
};
async function flushScores(){if(!account)return;for(const item of await storage('scores','getAll')){if(item.userId!==account.userId)continue;try{await api('/api/rhythkit/scores',item.score);await storage('scores','delete',item.score.clientScoreId);$('game-status').textContent=`${item.score.cameraMode === 'spin'?'Spin':'Lock'} pass recorded. Rank points require official Rhythia verification.`;}catch(error){if(error.status===409)await storage('scores','delete',item.score.clientScoreId);else {$('game-status').textContent='Pass queued: '+error.message;break;}}}}
async function startEngine(){
  if(engineStarted)return engineReady.promise;
  if(!Engine.isWebGLAvailable())throw new Error('WebGL is unavailable. Enable graphics acceleration to play.');
  let resolve,reject;const promise=new Promise((a,b)=>{resolve=a;reject=b;});engineReady={promise,resolve,reject};engineStarted=true;
  const timer=setTimeout(()=>reject(new Error('The game did not finish loading. Reload to retry.')),120000);
  window.gameEngine.startGame({onProgress:(a,b)=>{$('game-status').textContent=b?`Loading game ${Math.round(a/b*100)}%`:'Loading game…';},onPrintError:message=>{console.error(message);if(/SCRIPT ERROR|Parse Error/.test(message))reject(new Error(message));}}).catch(reject);
  try{await promise;}finally{clearTimeout(timer);}
}
async function play(map){try{$('game').hidden=false;await startEngine();if(menuWait)await menuWait;const saved=await storage('maps','get',map.id);if(!saved)throw new Error('Download this map first.');const path='/tmp/rhythians-'+map.id.replace(/[^a-zA-Z0-9_-]/g,'')+'.sspm';window.gameEngine.copyToFS(path,await saved.blob.arrayBuffer());activeAccount=account && !map.id.startsWith('local-') ? {...account}:null;window.rhythiansCommand(JSON.stringify({action:'play',path,map,spin}));$('canvas').focus();}catch(error){$('game-status').textContent=error.message;}}
$('back').onclick=()=>{$('game').hidden=true;if(window.rhythiansCommand){menuWait=new Promise(resolve=>{resolveMenu=resolve;});window.rhythiansCommand(JSON.stringify({action:'portal'}));}render();};
async function download(map,button,progress,label){if(downloadBusy)return;downloadBusy=true;button.disabled=true;progress.hidden=false;try{
  const response=await fetch(BASE+`/api/rhythkit/maps/${encodeURIComponent(map.id)}/download`,{headers:{Authorization:'Bearer '+account.token},credentials:'omit',signal:AbortSignal.timeout(180000)});
  if(!response.ok){const data=await response.json().catch(()=>({}));throw new Error(data.error||`Download failed (${response.status}).`);}
  const total=Number(response.headers.get('Content-Length'))||0;if(total>134217728)throw new Error('Map exceeds 128 MiB.');
  if(total){progress.max=total;progress.value=0;}else progress.removeAttribute('value');
  const reader=response.body.getReader(),chunks=[];let received=0;
  while(true){const {done,value}=await reader.read();if(done)break;received+=value.byteLength;if(received>134217728){await reader.cancel();throw new Error('Map exceeds 128 MiB.');}chunks.push(value);if(total)progress.value=received;label.textContent=total?`Downloading ${Math.round(received/total*100)}%`:`Downloading ${(received/1048576).toFixed(1)} MiB`;}
  const blob=new Blob(chunks);await saveMap(map,blob);button.textContent='Play';button.onclick=()=>play(map);label.textContent='Saved in this browser';
}catch(error){label.textContent=error.message;}finally{downloadBusy=false;button.disabled=false;progress.hidden=true;}}
async function saveMap(map,blob){validateSspm(await blob.arrayBuffer());await storage('maps','put',map.id,{map,blob});await storage('mapmeta','put',map.id,map);}
async function mapCard(map){const card=node('article',null,'card');card.append(picture(map.imageUrl,map.title));const body=node('div',null,'body');body.append(node('h2',map.title),node('p',`${map.artist||''} · ${map.mapper||''}`));const meta=node('div',null,'meta');meta.append(node('span',`${Number(map.rating||0).toFixed(2)} ★`,'rating'),node('span',map.isRanked?`Ranked · ${map.rankName}`:map.isLegacy?'Legacy':'Unranked','badge'));body.append(meta);const button=node('button'),progress=node('progress'),label=node('span','','download-label');progress.hidden=true;const saved=await storage('maps','getKey',map.id);button.textContent=saved?'Play':'Download';button.onclick=()=>saved?play(map):download(map,button,progress,label);body.append(button,progress,label);card.append(body);return card;}
async function showMaps(local,gen){const maps=local?(await storage('mapmeta','getAll')):(await api(`/api/rhythkit/maps?limit=40&offset=${offset}`));if(gen!==generation)return;const entries=local?maps.slice(offset,offset+40):maps.maps;hasMore=local?maps.length>offset+40:maps.hasMore;const grid=node('div',null,'grid');const cards=await Promise.all(entries.map(mapCard));if(gen!==generation)return;grid.append(...cards);$('content').append(grid);if(!entries.length)$('content').append(node('p',local?'Drop SSPM maps anywhere on this page, or download one from Maps.':'No maps on this page.'));$('pagination').hidden=false;$('prev').disabled=offset===0;$('next').disabled=!hasMore;$('page-number').textContent=`Page ${offset/40+1}`;}
async function profile(gen){const data=await api('/api/rhythkit/portal?page=profile');if(gen!==generation)return;const p=data.profile;const head=node('section',null,'profile-head');head.append(picture(p.avatar,p.username,'avatar'));const info=node('div');info.append(node('h2',p.displayName||p.username),node('p',p.title||'Rhythian'));head.append(info);$('content').append(head,node('p',p.bio||''));const stats=node('div',null,'stats');for(const [label,value] of [['RHP',p.rhp],['RPL',p.modes?.rpl],['RPS',p.modes?.rps],['Global rank',p.globalRank]]){const s=node('div',label,'stat');s.append(node('strong',value??0));stats.append(s);}$('content').append(stats);const link=node('a','Open profile and account linking on Rhythians');link.href=BASE+'/profile/'+encodeURIComponent(p.profileHandle);link.target='_blank';link.rel='noopener';$('content').append(link);showRank(p);const history=await api('/api/rhythkit/scores?limit=25');if(gen!==generation)return;$('content').append(node('h2','Recent client passes'));for(const score of history.scores){const row=node('div',null,'row');row.append(node('span',score.title),node('span',`${score.cameraMode === 'spin'?'Spin':'Lock'} · ${Number(score.accuracy).toFixed(2)}%`));$('content').append(row);}}
function showRank(p){if(!p.rank)return;$('rank').hidden=false;$('rank').replaceChildren(node('strong',`${p.rank.name} ${p.rank.isExpert?'':p.rank.tier} · ${p.rhp} RHP`));const progress=node('progress');progress.max=1;progress.value=p.rank.isExpert?1:Math.max(0,Math.min(1,p.rank.progressToNextTier||0));$('rank').append(progress);}
async function community(page,gen){const data=await api('/api/rhythkit/portal?page='+page);if(gen!==generation)return;if(page==='leaderboards'){const tabs=node('div',null,'tabs'),list=node('section');function display(mode){list.replaceChildren();const rows=mode==='rhp'?data.rhp:data.modes?.[mode]||[];rows.forEach((p,i)=>{const row=node('div',null,'row');row.append(node('span',i+1),picture(p.avatar,p.username,'avatar'),node('strong',p.displayName||p.username),node('span',p.points??p.rhp??0));list.append(row);});}for(const mode of ['rhp','lock','spin']){const b=node('button',mode==='rhp'?'RHP':mode==='spin'?'Spin · RPS':'Lock · RPL');b.onclick=()=>display(mode);tabs.append(b);}$('content').append(tabs,list);display('rhp');return;}
const grid=node('div',null,page==='clips'?'grid':'');for(const item of data[page==='clips'?'clips':'articles']||[]){const card=node('article',null,'card'),body=node('div',null,'body');body.append(node('h2',item.title),node('p',item.description||''));if(page==='clips'){card.append(picture(item.thumbnailUrl,item.title));if(item.videoUrl){const video=node('video');video.controls=true;video.preload='none';video.src=safeUrl(item.videoUrl);body.append(video);}const link=node('a','Open clip');link.href=BASE+'/clips/'+encodeURIComponent(item.id);link.target='_blank';link.rel='noopener';body.append(link);}else{const details=node('details'),summary=node('summary','Read article');details.append(summary,node('div',item.content||'','article'));body.append(details);}card.append(body);grid.append(card);}$('content').append(grid);}
async function cachedProfile(){if(profileCache?.userId===account?.userId && Date.now()-profileCache.time<120000)return profileCache.data;const data=await api('/api/rhythkit/portal?page=profile');profileCache={userId:account?.userId,time:Date.now(),data};return data;}
async function render(){const gen=++generation;const page=location.hash.slice(1)||'maps';$('title').textContent=({maps:'Maps',profile:'Your profile',leaderboards:'Leaderboards',wiki:'Wiki',clips:'Clips',library:'Downloaded maps'})[page]||'Maps';$('content').replaceChildren();$('pagination').hidden=true;$('rank').hidden=true;notice('');for(const a of document.querySelectorAll('nav a'))a.setAttribute('aria-current',a.hash===`#${page}`?'page':'false');if(!account && page!=='library'){notice('Sign in to link your Rhythians account. Downloaded maps remain available offline.');return;}try{if(page==='maps'||page==='library'){await showMaps(page==='library',gen);if(page==='maps'){const p=await cachedProfile();if(gen===generation)showRank(p.profile);}}else if(page==='profile')await profile(gen);else if(['leaderboards','wiki','clips'].includes(page))await community(page,gen);}catch(error){if(gen===generation)notice(error.message);}}
$('prev').onclick=()=>{offset=Math.max(0,offset-40);render();};$('next').onclick=()=>{offset+=40;render();};window.onhashchange=()=>{offset=0;render();};
async function importSspmFiles(files){
  try{
    let imported=0;
    for(const file of files){
      if(!/\.sspm$/i.test(file.name)||file.size>134217728)throw new Error('Choose SSPM files below 128 MiB each.');
      const id='local-'+crypto.randomUUID();
      await saveMap({id,title:file.name.replace(/\.sspm$/i,''),artist:'Local import',mapper:'Browser',isRanked:false,isLegacy:false},file);
      imported++;
    }
    if(imported){location.hash='library';await render();notice(`${imported} SSPM map${imported===1?'':'s'} imported and saved in this browser.`);}
  }catch(error){notice(error.message);}
}
$('import-sspm').onclick=()=>{$('sspm-picker').value='';$('sspm-picker').click();};
$('sspm-picker').onchange=async()=>importSspmFiles($('sspm-picker').files);
document.addEventListener('keydown',event=>{if((event.ctrlKey||event.metaKey)&&event.key.toLowerCase()==='o'){event.preventDefault();$('import-sspm').click();}});
$('fullscreen').onclick=async()=>{try{if(!document.fullscreenElement)await $('game').requestFullscreen();else await document.exitFullscreen();$('canvas').focus();}catch(error){$('game-status').textContent='Fullscreen unavailable: '+error.message;}};
document.addEventListener('fullscreenchange',()=>{$('fullscreen').textContent=document.fullscreenElement?'Exit fullscreen':'Fullscreen';});
window.addEventListener('dragover',event=>{event.preventDefault();$('drop').hidden=false;},true);window.addEventListener('dragleave',event=>{if(!event.relatedTarget)$('drop').hidden=true;},true);window.addEventListener('drop',async event=>{event.preventDefault();event.stopImmediatePropagation();$('drop').hidden=true;await importSspmFiles(event.dataTransfer.files);},true);
document.addEventListener('visibilitychange',()=>{if(document.hidden&&engineStarted)window.rhythiansCommand?.(JSON.stringify({action:'save'}));});window.addEventListener('online',flushScores);window.addEventListener('unhandledrejection',event=>notice(event.reason?.message||'An unexpected error occurred.'));
await render();flushScores();
