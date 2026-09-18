const BASE="https://www.rhythians.com";
const $=id=>document.getElementById(id);

const deviceInfo=(()=>{
  const ua=navigator.userAgent||"";
  const ios=/iPad|iPhone|iPod/i.test(ua)||(navigator.platform==="MacIntel"&&navigator.maxTouchPoints>1);
  const android=/Android/i.test(ua);
  return {ios,android,mobile:ios||android};
})();
let mobileInputMode="mouse";
let activeTouchId=null;

function isStandalone(){
  return navigator.standalone===true||window.matchMedia("(display-mode: standalone)").matches;
}
function showMobileSetup(view){
  $("launcher").hidden=true;
  $("game").hidden=true;
  $("mobile-setup").hidden=false;
  $("ios-install").hidden=view!=="install";
  $("android-unsupported").hidden=view!=="android";
  $("mobile-mode-choice").hidden=view!=="mode";
}
function dispatchTouchAsMouse(type,touch,buttons){
  const canvas=$("canvas");
  canvas.dispatchEvent(new MouseEvent(type,{
    bubbles:true,
    cancelable:true,
    view:window,
    clientX:touch.clientX,
    clientY:touch.clientY,
    screenX:touch.screenX,
    screenY:touch.screenY,
    button:0,
    buttons
  }));
}
function trackedTouch(list){
  return Array.from(list||[]).find(touch=>touch.identifier===activeTouchId)||null;
}
function enableTouchMouseBridge(){
  const canvas=$("canvas");
  if(canvas.dataset.touchMouseBridge==="1")return;
  canvas.dataset.touchMouseBridge="1";
  canvas.classList.add("touchscreen-mode");
  canvas.addEventListener("touchstart",event=>{
    if(mobileInputMode!=="touchscreen"||activeTouchId!==null)return;
    const touch=event.changedTouches[0];
    if(!touch)return;
    activeTouchId=touch.identifier;
    canvas.focus();
    dispatchTouchAsMouse("mousemove",touch,0);
    dispatchTouchAsMouse("mousedown",touch,1);
    event.preventDefault();
    event.stopImmediatePropagation();
  },{passive:false});
  canvas.addEventListener("touchmove",event=>{
    if(mobileInputMode!=="touchscreen"||activeTouchId===null)return;
    const touch=trackedTouch(event.touches)||trackedTouch(event.changedTouches);
    if(!touch)return;
    dispatchTouchAsMouse("mousemove",touch,1);
    event.preventDefault();
    event.stopImmediatePropagation();
  },{passive:false});
  const endTouch=event=>{
    if(mobileInputMode!=="touchscreen"||activeTouchId===null)return;
    const touch=trackedTouch(event.changedTouches);
    if(!touch)return;
    dispatchTouchAsMouse("mousemove",touch,1);
    dispatchTouchAsMouse("mouseup",touch,0);
    activeTouchId=null;
    event.preventDefault();
    event.stopImmediatePropagation();
  };
  canvas.addEventListener("touchend",endTouch,{passive:false});
  canvas.addEventListener("touchcancel",endTouch,{passive:false});
}
function enterClient(mode="mouse"){
  mobileInputMode=mode;
  window.rhythiansMobileInputMode=mode;
  document.documentElement.dataset.inputMode=mode;
  $("mobile-setup").hidden=true;
  $("launcher").hidden=false;
  if(mode==="touchscreen")enableTouchMouseBridge();
  setStage("home");
}
function initDeviceGate(){
  if(deviceInfo.android){
    showMobileSetup("android");
    return;
  }
  if(deviceInfo.ios&&!isStandalone()){
    showMobileSetup("install");
    return;
  }
  if(deviceInfo.ios&&isStandalone()){
    showMobileSetup("mode");
    return;
  }
  enterClient("mouse");
}

const memoryStorage=new Map();
let db=null;
try{
  db=await Promise.race([
    new Promise((resolve,reject)=>{
      if(!("indexedDB" in window)){reject(new Error("IndexedDB unavailable"));return;}
      const request=indexedDB.open("RhythiansBrowser",3);
      request.onupgradeneeded=()=>{
        for(const name of ["account","settings"])if(!request.result.objectStoreNames.contains(name))request.result.createObjectStore(name);
      };
      request.onsuccess=()=>resolve(request.result);
      request.onerror=()=>reject(request.error||new Error("IndexedDB failed"));
      request.onblocked=()=>reject(new Error("IndexedDB blocked"));
    }),
    new Promise((_,reject)=>setTimeout(()=>reject(new Error("IndexedDB timed out")),4000))
  ]);
}catch{}

function fallbackStorageKey(store,key){return `rhythians:${store}:${key}`;}
function fallbackGet(store,key){
  const storageKey=fallbackStorageKey(store,key);
  try{
    const raw=localStorage.getItem(storageKey);
    if(raw!==null)return JSON.parse(raw);
  }catch{}
  return memoryStorage.get(storageKey)??null;
}
function fallbackPut(store,key,value){
  const storageKey=fallbackStorageKey(store,key);
  memoryStorage.set(storageKey,value);
  try{localStorage.setItem(storageKey,JSON.stringify(value));}catch{}
  return value;
}
function fallbackDelete(store,key){
  const storageKey=fallbackStorageKey(store,key);
  memoryStorage.delete(storageKey);
  try{localStorage.removeItem(storageKey);}catch{}
}
async function storage(store,method,key,value){
  if(db){
    try{
      return await new Promise((resolve,reject)=>{
        const tx=db.transaction(store,method==="get"?"readonly":"readwrite");
        const object=tx.objectStore(store);
        const request=method==="put"?object.put(value,key):object[method](key);
        tx.oncomplete=()=>resolve(request.result);
        tx.onerror=tx.onabort=()=>reject(tx.error||request.error);
      });
    }catch{}
  }
  if(method==="get")return fallbackGet(store,key);
  if(method==="put")return fallbackPut(store,key,value);
  if(method==="delete"){fallbackDelete(store,key);return;}
  return null;
}

let savedAccount=await storage("account","get","current").catch(()=>null);
let sessionAccount=null;
let engineStarted=false;
let engineReady=null;
let loginGeneration=0;
let switchingAccount=false;

function status(message){$("launch-status").textContent=message||"";}
function setStage(stage){
  $("launch-home").hidden=stage!=="home";
  $("session-choice").hidden=stage!=="choice";
  $("signin-state").hidden=stage!=="signin";
}
function showLauncher(stage="choice"){
  switchingAccount=engineStarted;
  $("launcher").hidden=false;
  setStage(stage);
  status("");
}
function accountLabel(){
  $("account-state").textContent=sessionAccount?sessionAccount.username:"Guest";
}
async function api(path,body,account=savedAccount){
  const controller=new AbortController();
  const timer=setTimeout(()=>controller.abort(),45000);
  let response;
  try{
    response=await fetch(BASE+path,{
      method:body===undefined?"GET":"POST",
      headers:{
        ...(body===undefined?{}:{"Content-Type":"application/json"}),
        ...(account?.token?{Authorization:"Bearer "+account.token}:{})
      },
      ...(body===undefined?{}:{body:JSON.stringify(body)}),
      credentials:"omit",
      cache:"no-store",
      signal:controller.signal
    });
  }catch(error){
    const wrapped=new Error(error?.name==="AbortError"?"Rhythians timed out. Check your connection and try again.":"Could not reach Rhythians. Check your connection and try again.");
    wrapped.cause=error;
    throw wrapped;
  }finally{
    clearTimeout(timer);
  }
  const data=await response.json().catch(()=>({error:"Invalid server response."}));
  if(!response.ok||data.ok===false){
    const error=new Error(data.error||`Request failed (${response.status}).`);
    error.status=response.status;
    throw error;
  }
  return data;
}
async function validateSavedAccount(){
  if(!savedAccount?.token)return null;
  try{
    const data=await api("/api/rhythkit/status",undefined,savedAccount);
    if(data.username)savedAccount.username=data.username;
    if(data.userId)savedAccount.userId=data.userId;
    if(data.installationId)savedAccount.installationId=data.installationId;
    await storage("account","put","current",savedAccount);
    return savedAccount;
  }catch(error){
    if(error?.status===401||error?.status===403){
      savedAccount=null;
      await storage("account","delete","current").catch(()=>{});
      return null;
    }
    return savedAccount;
  }
}
async function startEngine(){
  if(engineStarted&&engineReady)return engineReady;
  if(!Engine.isWebGLAvailable())throw new Error("WebGL is unavailable. Enable graphics acceleration and reload.");
  engineStarted=true;
  engineReady=new Promise((resolve,reject)=>{
    let settled=false;
    const timeout=setTimeout(()=>finish(reject,new Error("The client did not finish loading. Reload and try again.")),180000);
    const finish=(fn,value)=>{
      if(settled)return;
      settled=true;
      clearTimeout(timeout);
      fn(value);
    };
    window.rhythiansReady=text=>{
      try{
        const state=JSON.parse(text);
        if(!state.persistent)$("game-status").textContent="Browser persistence is unavailable; local settings may be temporary.";
        window.rhythiansPersistUserData?.().catch(()=>{});
        finish(resolve,state);
      }catch(error){
        finish(reject,error);
      }
    };
    window.gameEngine.startGame({
      onProgress:(current,total)=>{
        $("game-status").textContent=total?`Loading Rhythians ${Math.round(current/total*100)}%`:"Loading Rhythians…";
      },
      onPrintError:message=>{
        if(/SCRIPT ERROR|Parse Error|does not have a library for the current platform/.test(message))finish(reject,new Error(message));
      }
    }).catch(error=>finish(reject,error));
  });
  try{
    return await engineReady;
  }catch(error){
    engineStarted=false;
    engineReady=null;
    throw error;
  }
}
async function applySession(account){
  sessionAccount=account||null;
  accountLabel();
  $("game").hidden=false;
  $("launcher").hidden=true;
  $("game-status").textContent="Loading Rhythians…";
  await new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve)));
  try{
    await startEngine();
  }catch(error){
    $("game").hidden=true;
    $("launcher").hidden=false;
    setStage("choice");
    status(error?.message||"The Rhythians client could not start.");
    throw error;
  }
  if(sessionAccount){
    window.rhythiansCommand?.(JSON.stringify({action:"auth",account:sessionAccount}));
    $("game-status").textContent=`Connected as ${sessionAccount.username}. Syncing ranks and maps…`;
  }else{
    window.rhythiansCommand?.(JSON.stringify({action:"guest"}));
    $("game-status").textContent="Guest mode · account ranks and online map sync are unavailable.";
  }
  $("canvas").focus();
}
async function beginSignin(force=false){
  const attempt=++loginGeneration;
  setStage("signin");
  status("");
  $("signin-code").textContent="…";
  $("signin-copy").textContent="Checking your Rhythians session…";
  $("signin-link").hidden=true;
  let authTab=null;
  try{
    authTab=window.open("about:blank","rhythians-web-auth");
    if(authTab)authTab.opener=null;
  }catch{}
  if(!force){
    const current=await validateSavedAccount();
    if(current&&attempt===loginGeneration){
      if(authTab&&!authTab.closed)try{authTab.close();}catch{}
      await applySession(current);
      return;
    }
  }
  try{
    $("signin-copy").textContent="Creating a secure Rhythians login request…";
    const data=await api("/api/rhythkit/device/start",{},null);
    if(attempt!==loginGeneration)return;
    const verification=new URL(data.verificationUrl);
    if(verification.origin!==BASE)throw new Error("Unexpected authorization website.");
    verification.searchParams.set("client","web");
    $("signin-code").textContent=data.userCode;
    $("signin-copy").textContent="Confirm this browser on the Rhythians tab. This page will connect automatically after approval.";
    $("signin-link").href=verification.href;
    $("signin-link").hidden=false;
    if(authTab)authTab.location.href=verification.href;
    const expires=Date.now()+Number(data.expiresIn||300)*1000;
    while(attempt===loginGeneration&&Date.now()<expires){
      await new Promise(resolve=>setTimeout(resolve,3000));
      if(attempt!==loginGeneration)return;
      const result=await api("/api/rhythkit/device/poll",{deviceCode:data.deviceCode},null);
      if(result.pending)continue;
      if(result.authorized&&result.token){
        savedAccount={
          token:result.token,
          userId:result.userId,
          username:result.username,
          installationId:result.installationId
        };
        await storage("account","put","current",savedAccount);
        if(authTab&&!authTab.closed)authTab.close();
        await applySession(savedAccount);
        return;
      }
    }
    if(attempt===loginGeneration)throw new Error("The login request expired. Try again.");
  }catch(error){
    if(authTab&&!authTab.closed)try{authTab.close();}catch{}
    if(attempt===loginGeneration){
      $("signin-copy").textContent="Rhythians sign-in could not finish.";
      status(error.message);
    }
  }
}

$("launch-play").onclick=()=>showLauncher("choice");
$("back-launch").onclick=()=>setStage("home");
$("signin-rhythians").onclick=()=>beginSignin(false);
$("play-guest").onclick=()=>applySession(null).catch(error=>status(error.message));
$("cancel-signin").onclick=()=>{
  loginGeneration++;
  setStage("choice");
  status("");
};
$("change-account").onclick=()=>{
  window.rhythiansCommand?.(JSON.stringify({action:"save"}));
  window.rhythiansPersistUserData?.().catch(()=>{});
  showLauncher("choice");
};

window.rhythiansRequestSignin=()=>showLauncher("choice");
window.rhythiansAuthChanged=async text=>{
  try{
    const state=JSON.parse(text);
    if(state.loggedIn){
      if(sessionAccount){
        sessionAccount={...sessionAccount,username:state.username||sessionAccount.username,userId:state.userId||sessionAccount.userId,installationId:state.installationId||sessionAccount.installationId};
      }
    }else{
      sessionAccount=null;
      savedAccount=null;
      await storage("account","delete","current").catch(()=>{});
    }
    accountLabel();
  }catch{}
};
window.rhythiansAccountApplied=text=>{
  try{
    const state=JSON.parse(text);
    $("game-status").textContent=state.loggedIn?`Connected as ${state.username}. Maps and ranks are syncing.`:"Guest mode";
  }catch{}
};
window.rhythiansCatalogReady=count=>{
  $("game-status").textContent=sessionAccount?`${Number(count)||0} Rhythians maps synced · ${sessionAccount.username}`:"Guest mode";
};
window.rhythiansError=message=>{$("game-status").textContent=String(message||"Rhythians client error");};
window.rhythiansSelected=()=>{$("game-status").textContent="Map selected. Choose modifiers and press Play.";};
window.rhythiansImported=(name,ok,message)=>{
  $("game-status").textContent=ok?`${name} imported into your Play library.`:String(message||"Import failed.");
  if(ok)window.rhythiansPersistUserData?.().catch(()=>{});
};
window.rhythiansMode=()=>{};
window.rhythiansScore=async text=>{
  if(!sessionAccount)return;
  try{
    const score={...JSON.parse(text),clientScoreId:crypto.randomUUID(),completedAt:new Date().toISOString()};
    await api("/api/rhythkit/scores",score,sessionAccount);
    $("game-status").textContent=`${score.cameraMode==="spin"?"Spin":"Lock"} pass recorded on Rhythians.`;
  }catch(error){
    $("game-status").textContent="Score could not be submitted: "+error.message;
  }
};
window.rhythiansScoreResult=(ok,message)=>{
  if(ok){
    $("game-status").textContent=message==="already"?"Score already recorded on Rhythians.":"Pass recorded on Rhythians.";
    window.rhythiansPersistUserData?.().catch(()=>{});
  }else{
    $("game-status").textContent=String(message||"Score queued and will retry when Rhythians reconnects.");
  }
};

async function importFiles(files){
  if(!engineStarted||!engineReady){
    $("game-status").textContent="The client is still starting. Try Import again when the menu appears.";
    return;
  }
  try{
    await engineReady;
  }catch(error){
    $("game-status").textContent=error?.message||"The client is not ready to import maps.";
    return;
  }
  let imported=0;
  for(const file of Array.from(files||[])){
    if(!/\.sspm$/i.test(file.name))continue;
    if(file.size>134217728){
      $("game-status").textContent=`${file.name} is larger than 128 MiB.`;
      continue;
    }
    try{
      const id=(crypto.randomUUID?.()||String(Date.now())+Math.random().toString(16).slice(2)).replaceAll("-","");
      const path=`/tmp/rhythians-import-${id}.sspm`;
      window.gameEngine.copyToFS(path,await file.arrayBuffer());
      window.rhythiansCommand?.(JSON.stringify({action:"import",path,name:file.name}));
      imported++;
    }catch(error){
      $("game-status").textContent=`Could not import ${file.name}: ${error?.message||"browser file error"}`;
    }
  }
  if(imported)$("game-status").textContent=`Importing ${imported} SSPM map${imported===1?"":"s"}…`;
}
$("import-sspm").onclick=()=>{
  const picker=$("sspm-picker");
  picker.value="";
  try{
    if(typeof picker.showPicker==="function")picker.showPicker();
    else picker.click();
  }catch{
    picker.click();
  }
};
$("sspm-picker").onchange=()=>importFiles($("sspm-picker").files);
document.addEventListener("keydown",event=>{
  if((event.ctrlKey||event.metaKey)&&event.key.toLowerCase()==="o"&&!$("game").hidden){
    event.preventDefault();
    $("import-sspm").click();
  }
});
window.addEventListener("dragover",event=>{
  if($("game").hidden)return;
  event.preventDefault();
  $("drop").hidden=false;
},true);
window.addEventListener("dragleave",event=>{
  if(!event.relatedTarget)$("drop").hidden=true;
},true);
window.addEventListener("drop",event=>{
  if($("game").hidden)return;
  event.preventDefault();
  event.stopImmediatePropagation();
  $("drop").hidden=true;
  importFiles(event.dataTransfer.files);
},true);

const fullscreenElement=()=>document.fullscreenElement||document.webkitFullscreenElement||null;
function updateFullscreenButton(){
  $("fullscreen").textContent=fullscreenElement()||$("game").classList.contains("immersive-fallback")?"Exit fullscreen":"Fullscreen";
}
$("fullscreen").onclick=async()=>{
  const game=$("game");
  try{
    if(fullscreenElement()){
      const exit=document.exitFullscreen||document.webkitExitFullscreen;
      if(exit)await exit.call(document);
    }else{
      const request=game.requestFullscreen||game.webkitRequestFullscreen;
      if(request){
        await request.call(game);
      }else{
        game.classList.toggle("immersive-fallback");
      }
    }
  }catch(error){
    game.classList.toggle("immersive-fallback");
    $("game-status").textContent=game.classList.contains("immersive-fallback")?"Immersive browser mode enabled.":"Fullscreen unavailable: "+(error?.message||"browser restriction");
  }
  updateFullscreenButton();
  $("canvas").focus();
};
document.addEventListener("fullscreenchange",updateFullscreenButton);
document.addEventListener("webkitfullscreenchange",updateFullscreenButton);
window.addEventListener("online",()=>{
  if(engineStarted&&sessionAccount)window.rhythiansCommand?.(JSON.stringify({action:"flush"}));
});
document.addEventListener("visibilitychange",()=>{
  if(document.hidden&&engineStarted)window.rhythiansCommand?.(JSON.stringify({action:"save"}));
});
window.addEventListener("beforeunload",()=>{if(engineStarted)window.rhythiansCommand?.(JSON.stringify({action:"save"}));});
$("mobile-mouse").onclick=()=>enterClient("mouse");
$("mobile-touch").onclick=()=>enterClient("touchscreen");
accountLabel();
initDeviceGate();
