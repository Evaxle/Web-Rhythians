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

const db=await new Promise((resolve,reject)=>{
  const request=indexedDB.open("RhythiansBrowser",3);
  request.onupgradeneeded=()=>{
    for(const name of ["account","settings"])if(!request.result.objectStoreNames.contains(name))request.result.createObjectStore(name);
  };
  request.onsuccess=()=>resolve(request.result);
  request.onerror=()=>reject(request.error);
});

function storage(store,method,key,value){
  return new Promise((resolve,reject)=>{
    const tx=db.transaction(store,method==="get"?"readonly":"readwrite");
    const object=tx.objectStore(store);
    const request=method==="put"?object.put(value,key):object[method](key);
    tx.oncomplete=()=>resolve(request.result);
    tx.onerror=tx.onabort=()=>reject(tx.error||request.error);
  });
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
  const response=await fetch(BASE+path,{
    method:body===undefined?"GET":"POST",
    headers:{
      ...(body===undefined?{}:{"Content-Type":"application/json"}),
      ...(account?.token?{Authorization:"Bearer "+account.token}:{})
    },
    ...(body===undefined?{}:{body:JSON.stringify(body)}),
    credentials:"omit",
    signal:AbortSignal.timeout(45000)
  });
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
  }catch{
    savedAccount=null;
    await storage("account","delete","current").catch(()=>{});
    return null;
  }
}
async function startEngine(){
  if(engineStarted)return engineReady;
  if(!Engine.isWebGLAvailable())throw new Error("WebGL is unavailable. Enable graphics acceleration and reload.");
  engineStarted=true;
  engineReady=new Promise((resolve,reject)=>{
    const timeout=setTimeout(()=>reject(new Error("The client did not finish loading. Reload and try again.")),120000);
    window.rhythiansReady=text=>{
      clearTimeout(timeout);
      const state=JSON.parse(text);
      if(!state.persistent)$("game-status").textContent="Browser persistence is unavailable; local settings may be temporary.";
      window.rhythiansPersistUserData?.().catch(()=>{});
      resolve(state);
    };
    window.gameEngine.startGame({
      onProgress:(current,total)=>{
        $("game-status").textContent=total?`Loading Rhythians ${Math.round(current/total*100)}%`:"Loading Rhythians…";
      },
      onPrintError:message=>{
        if(/SCRIPT ERROR|Parse Error|does not have a library for the current platform/.test(message))reject(new Error(message));
      }
    }).catch(reject);
  });
  return engineReady;
}
async function applySession(account){
  sessionAccount=account||null;
  accountLabel();
  $("game").hidden=false;
  $("launcher").hidden=true;
  $("game-status").textContent="Loading Rhythians…";
  await startEngine();
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
  if(!force){
    const current=await validateSavedAccount();
    if(current&&attempt===loginGeneration){
      await applySession(current);
      return;
    }
  }
  let authTab=null;
  try{
    authTab=window.open("about:blank","_blank");
    if(authTab)authTab.opener=null;
  }catch{}
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
$("change-account").onclick=()=>showLauncher("choice");

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

async function importFiles(files){
  if(!engineStarted){
    status("Start the client before importing maps.");
    return;
  }
  await engineReady;
  let imported=0;
  for(const file of files){
    if(!/\.sspm$/i.test(file.name))continue;
    if(file.size>134217728){
      $("game-status").textContent=`${file.name} is larger than 128 MiB.`;
      continue;
    }
    const id=crypto.randomUUID().replaceAll("-","");
    const path=`/tmp/rhythians-import-${id}.sspm`;
    window.gameEngine.copyToFS(path,await file.arrayBuffer());
    window.rhythiansCommand?.(JSON.stringify({action:"import",path,name:file.name}));
    imported++;
  }
  if(imported)$("game-status").textContent=`Importing ${imported} SSPM map${imported===1?"":"s"}…`;
}
$("import-sspm").onclick=()=>{$("sspm-picker").value="";$("sspm-picker").click();};
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

$("fullscreen").onclick=async()=>{
  try{
    if(!document.fullscreenElement)await $("game").requestFullscreen();
    else await document.exitFullscreen();
    $("canvas").focus();
  }catch(error){
    $("game-status").textContent="Fullscreen unavailable: "+error.message;
  }
};
document.addEventListener("fullscreenchange",()=>{
  $("fullscreen").textContent=document.fullscreenElement?"Exit fullscreen":"Fullscreen";
});
document.addEventListener("visibilitychange",()=>{
  if(document.hidden&&engineStarted)window.rhythiansCommand?.(JSON.stringify({action:"save"}));
});
window.addEventListener("beforeunload",()=>{if(engineStarted)window.rhythiansCommand?.(JSON.stringify({action:"save"}));});
$("mobile-mouse").onclick=()=>enterClient("mouse");
$("mobile-touch").onclick=()=>enterClient("touchscreen");
accountLabel();
initDeviceGate();
