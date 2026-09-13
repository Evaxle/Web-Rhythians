#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT_BIN="${GODOT_BIN:-godot}"
git submodule update --init --recursive
if git -C source apply --check ../patches/web.patch; then
  git -C source apply ../patches/web.patch
elif ! git -C source apply --reverse --check ../patches/web.patch; then
  echo 'The source conflicts with the web patch.' >&2
  exit 1
fi
python3 - <<'PY'
from pathlib import Path
root = Path("source")
prod = "https://www.rhythians.com"
for rel in ["project.godot", "web/app.js"]:
    path = root / rel
    text = path.read_text()
    text = text.replace("https://rhythians.vercel.app", prod)
    path.write_text(text)
shell_path = root / "web/shell.html"
shell = shell_path.read_text()
runtime = """<script>
window.rhythiansPersistUserData=()=>new Promise((resolve,reject)=>{
  const fs=globalThis.FS||(globalThis.Module&&globalThis.Module.FS);
  if(!fs||typeof fs.syncfs!=='function'){resolve(false);return;}
  fs.syncfs(false,error=>error?reject(error):resolve(true));
});
if(navigator.storage&&navigator.storage.persist)navigator.storage.persist().catch(()=>{});
document.addEventListener('visibilitychange',()=>{if(document.visibilityState==='hidden')window.rhythiansPersistUserData().catch(()=>{});});
addEventListener('pagehide',()=>window.rhythiansPersistUserData().catch(()=>{}));
setInterval(()=>window.rhythiansPersistUserData().catch(()=>{}),10000);
</script>"""
if "rhythiansPersistUserData" not in shell:
    shell = shell.replace("$GODOT_HEAD_INCLUDE", "$GODOT_HEAD_INCLUDE" + runtime)
shell = shell.replace('<a href="#profile">Profile</a><a href="#leaderboards">Leaderboards</a>', '<a href="#profile">Profile</a><a href="#users">Users</a><a href="#leaderboards">Leaderboards</a>')
shell_path.write_text(shell)
app_path = root / "web/app.js"
app = app_path.read_text()
marker = "async function cachedProfile()"
user_code = """function renderUserProfile(p){$('content').replaceChildren();const back=node('button','Back to users');back.onclick=()=>{location.hash='users';render();};$('content').append(back);const head=node('section',null,'profile-head');head.append(picture(p.avatar,p.username,'avatar'));const info=node('div');info.append(node('h2',p.displayName||p.username),node('p',p.title||'Rhythian'));head.append(info);$('content').append(head,node('p',p.bio||''));const stats=node('div',null,'stats');for(const [label,value] of [['RHP',p.rhp],['RPL',p.modes?.rpl],['RPS',p.modes?.rps],['Global rank',p.globalRank],['Challenge level',p.challengeLevel]]){const s=node('div',label,'stat');s.append(node('strong',value??0));stats.append(s);}$('content').append(stats);const meta=node('p',[p.online?'Online':'Offline',p.country,p.verified?'Verified':null].filter(Boolean).join(' · '));$('content').append(meta);if(p.tags?.length)$('content').append(node('p',p.tags.map(t=>t.name).join(' · ')));const link=node('a','Open full profile on Rhythians');link.href=BASE+'/profile/'+encodeURIComponent(p.profileHandle);link.target='_blank';link.rel='noopener';$('content').append(link);}
async function users(gen){const form=node('form',null,'user-search'),input=node('input'),button=node('button','Search'),results=node('section');input.type='search';input.placeholder='Search username or display name';input.autocomplete='off';input.maxLength=64;form.append(input,button);$('content').append(form,results);async function search(){const q=input.value.trim();button.disabled=true;try{const data=await api('/api/rhythkit/portal?page=search&q='+encodeURIComponent(q));if(gen!==generation)return;results.replaceChildren();if(!data.users?.length){results.append(node('p','No users found.'));return;}for(const p of data.users){const row=node('div',null,'row');row.append(picture(p.avatar,p.username,'avatar'));const name=node('div');name.append(node('strong',p.displayName||p.username),node('p','@'+p.profileHandle+(p.online?' · Online':'')));const view=node('button','View profile');view.onclick=async()=>{view.disabled=true;try{const data=await api('/api/rhythkit/portal?page=profile&handle='+encodeURIComponent(p.profileHandle));if(gen===generation)renderUserProfile(data.profile);}catch(error){notice(error.message);}finally{view.disabled=false;}};row.append(name,node('span',`${p.rhp??0} RHP`),view);results.append(row);}}finally{button.disabled=false;}}form.onsubmit=event=>{event.preventDefault();search();};await search();}
"""
if "async function users(gen)" not in app:
    if marker not in app:
        raise SystemExit("Could not locate profile cache insertion point")
    app = app.replace(marker, user_code + marker)
app = app.replace("profile:'Your profile',leaderboards:'Leaderboards'", "profile:'Your profile',users:'Users',leaderboards:'Leaderboards'")
app = app.replace("else if(page==='profile')await profile(gen);else if(['leaderboards','wiki','clips'].includes(page))", "else if(page==='profile')await profile(gen);else if(page==='users')await users(gen);else if(['leaderboards','wiki','clips'].includes(page))")
app_path.write_text(app)
css_path = root / "web/app.css"
css = css_path.read_text()
extra = ".user-search{display:flex;gap:10px;margin-bottom:24px}.user-search input{flex:1;min-width:0;background:#151a25;color:white;border:1px solid var(--line);border-radius:10px;padding:11px 14px;font:inherit}.user-search input:focus{outline:2px solid var(--accent);outline-offset:1px}"
if ".user-search{" not in css:
    css += extra
css_path.write_text(css)
PY
python3 - <<'PY'
from pathlib import Path
import base64
root = Path('source')
logo = base64.b64decode((root / 'web/logo.b64').read_text())
for name in ['logo.png', 'icon.png', 'splash.png', 'rhythians.png', 'sspicon.png']:
    (root / 'assets/images/branding' / name).write_bytes(logo)
(root / 'web/logo.png').write_bytes(logo)
PY
grep -q "https://www.rhythians.com" source/web/app.js
grep -q 'networking/rhythians_url="https://www.rhythians.com"' source/project.godot
grep -q "RhythiansBrowser" source/web/app.js
grep -q "rhythiansPersistUserData" source/web/shell.html
grep -q 'href="#users"' source/web/shell.html
grep -q "async function users(gen)" source/web/app.js
grep -q "page=profile&handle=" source/web/app.js
if grep -Rqs "https://rhythians.vercel.app" source/web source/project.godot; then exit 1; fi
mkdir -p source/bundled_maps source/build/web
find maps -maxdepth 1 -type f -iname '*.sspm' -exec cp {} source/bundled_maps/ \;
python3 source/web/tests/make_fixtures.py
node source/web/tests/sspm.mjs
"$GODOT_BIN" --path source --export-pack Web /tmp/rhythians-import.pck > /tmp/rhythians-import.log 2>&1
"$GODOT_BIN" --path source --export Web build/web/index.html 2>&1 | tee /tmp/rhythians-export.log
if grep -Eq 'SCRIPT ERROR|Parse Error|Failed loading resource' /tmp/rhythians-export.log; then exit 1; fi
test_data=$(mktemp -d)
timeout 30s env XDG_DATA_HOME="$test_data" "$GODOT_BIN" --path source web/tests/Smoke.tscn 2>&1 | tee /tmp/rhythians-smoke.log
grep -q 'SMOKE_FAILURES=0' /tmp/rhythians-smoke.log
if grep -Eq 'SCRIPT ERROR|FAIL:' /tmp/rhythians-smoke.log; then exit 1; fi
cp source/web/app.js source/web/sspm.mjs source/web/app.css source/web/logo.png source/build/web/
cp source/web/logo.png source/build/web/favicon.ico
test -s source/build/web/index.wasm
test -s source/build/web/index.pck
touch source/build/web/.nojekyll
