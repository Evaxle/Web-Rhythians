const $ = id => document.getElementById(id);
const playButton = $('play');
const launcher = $('launcher');
const client = $('client');
const canvas = $('canvas');
const status = $('status');
const clientStatus = $('client-status');
const picker = $('sspm-picker');
let engineStarted = false;
let enginePromise;
let readyResolve;
let readyReject;
let statusTimer;

function setStatus(message) {
  status.textContent = message;
}

function setClientStatus(message, hold = false) {
  clearTimeout(statusTimer);
  clientStatus.textContent = message;
  clientStatus.hidden = !message;
  if (message && !hold) {
    statusTimer = setTimeout(() => {
      clientStatus.hidden = true;
      clientStatus.textContent = '';
    }, 3500);
  }
}

function command(payload) {
  if (typeof window.rhythiansCommand === 'function') {
    window.rhythiansCommand(JSON.stringify(payload));
  }
}

window.rhythiansReady = text => {
  try {
    const state = JSON.parse(text);
    if (!state.persistent) setClientStatus('Persistent browser storage is unavailable. Imported maps may not survive a reload.', true);
  } catch {}
  readyResolve?.();
  readyResolve = undefined;
  readyReject = undefined;
};

window.rhythiansError = message => setClientStatus(String(message || 'The client reported an error.'), true);
window.rhythiansSelected = () => {};
window.rhythiansMode = () => {};
window.rhythiansScore = () => {};
window.rhythiansImported = (count, message) => {
  const total = Number(count) || 0;
  setClientStatus(message || `${total} SSPM map${total === 1 ? '' : 's'} imported.`);
  window.rhythiansPersistUserData?.().catch(() => {});
};
window.rhythiansPickSspm = () => {
  picker.value = '';
  picker.click();
};

async function startEngine() {
  if (enginePromise) return enginePromise;
  if (!Engine.isWebGLAvailable()) throw new Error('WebGL is unavailable. Enable graphics acceleration and reload.');
  engineStarted = true;
  enginePromise = new Promise(async (resolve, reject) => {
    const ready = new Promise((readyDone, readyFail) => {
      readyResolve = readyDone;
      readyReject = readyFail;
    });
    const timer = setTimeout(() => readyReject?.(new Error('The Rhythians client did not finish loading. Reload and try again.')), 120000);
    window.gameEngine.startGame({
      onProgress: (loaded, total) => {
        const percent = total ? Math.round(loaded / total * 100) : 0;
        setStatus(total ? `Loading client ${percent}%` : 'Loading client…');
      },
      onPrintError: message => {
        console.error(message);
        if (/SCRIPT ERROR|Parse Error/.test(message)) readyReject?.(new Error(message));
      }
    }).catch(error => readyReject?.(error));
    try {
      await ready;
      clearTimeout(timer);
      resolve();
    } catch (error) {
      clearTimeout(timer);
      reject(error);
    }
  });
  return enginePromise;
}

async function launch() {
  playButton.disabled = true;
  setStatus('Starting Rhythians…');
  client.hidden = false;
  try {
    await startEngine();
    launcher.hidden = true;
    setStatus('');
    canvas.focus();
  } catch (error) {
    client.hidden = true;
    playButton.disabled = false;
    setStatus(error?.message || 'Could not start the client.');
    enginePromise = undefined;
    engineStarted = false;
  }
}

async function importFiles(files) {
  if (!engineStarted || !files.length) return;
  const imported = [];
  try {
    for (const file of files) {
      if (!/\.sspm$/i.test(file.name)) throw new Error('Only .sspm map files can be imported.');
      if (file.size > 134217728) throw new Error(`${file.name} is larger than 128 MiB.`);
      const id = crypto.randomUUID().replaceAll('-', '');
      const path = `/tmp/rhythians-import-${id}.sspm`;
      window.gameEngine.copyToFS(path, await file.arrayBuffer());
      imported.push({ path, name: file.name });
    }
    setClientStatus(`Importing ${imported.length} map${imported.length === 1 ? '' : 's'}…`, true);
    command({ action: 'import', files: imported });
  } catch (error) {
    setClientStatus(error?.message || 'Could not import the SSPM map.', true);
  }
}

playButton.addEventListener('click', launch);
picker.addEventListener('change', () => importFiles([...picker.files]));
document.addEventListener('visibilitychange', () => {
  if (document.hidden && engineStarted) command({ action: 'save' });
});
window.addEventListener('pagehide', () => {
  if (engineStarted) command({ action: 'save' });
});
