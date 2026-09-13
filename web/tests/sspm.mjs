import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { validateSspm } from '../sspm.mjs';
const buffer = bytes => bytes.buffer.slice(bytes.byteOffset,bytes.byteOffset+bytes.byteLength);
for(const version of [1,2]){
 const bytes=readFileSync(new URL(`v${version}.sspm`,import.meta.url));
 assert.equal(validateSspm(buffer(bytes)),version);
 assert.throws(()=>validateSspm(buffer(bytes.subarray(0,bytes.length-2))));
 const bad=Buffer.from(bytes);bad[0]=0;assert.throws(()=>validateSspm(buffer(bad)));
}
const root=new URL('../../bundled_maps/',import.meta.url);
try{for(const file of readdirSync(root)){if(/\.sspm$/i.test(file))validateSspm(buffer(readFileSync(new URL(file,root))));}}catch(error){if(error.code!=='ENOENT')throw error;}
console.log('SSPM_CHECKS=6');
