'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const Module = require('node:module');
const vm = require('node:vm');
const { test } = require('node:test');

const scriptPath = path.join(__dirname, '..', 'Patch-Codex.ps1');
const engine = fs.readFileSync(scriptPath, 'utf8').match(/\$engineCode = @'\r?\n([\s\S]*?)\r?\n'@/)[1];
const loaded = new Module(scriptPath, module);
loaded._compile(engine.replace('if (true) {', 'if (false) {'), scriptPath);
const { transformWebpackPermissions } = loaded.exports;
const source = `export const __webpack_modules__={eYlV(e,t,n){
var i=n("thread"),p=n("atoms"),_=n("feature"),b=n("adjust"),u=n("client");
async function config(e,t){await (0,u.V)(e,t).sendRequest("config/read")}
function J(e,t,n,r,a){if(null==t)return null;let o=(0,i.JXB)(t);if(null!=r){if(r!==n)return null}else if(e.get(p.Qk,o)!==n)return null;let s=e.get(p.we,o),l=e.get(p.JN,o),d=null!=a&&l===a&&e.get(_.a,n)?(0,b.o)(s,e.get(p.h2,o)):s;if(null==d)return null;let c=(0,i.weu)(d);return null==c?null:{agentMode:c,permissions:d,permissionProfileId:d.activePermissionProfile?.id??null,sourceCwd:l}}
function next(){}
async function local(e,t,n,r,a){return {sourcePermissionSelection:J(e,t,n,r,a)}}
async function worktree(e,t,n,r){return {sourcePermissionSelection:J(e,t,n,r)}}
t.local=local;t.worktree=worktree;
}};
// sourceMappingURL=fixture.map`;

function transformed(sources = new Map([['fixture.js', source]])) {
  return transformWebpackPermissions(sources);
}
function entrypoints(code, permissions, adjusted) {
  const client = {
    async getThreadListSummary() { return { hostId: 'local' }; },
    async getCurrentPermissions() { return permissions; },
    async getFollowUpContext() { return { cwd: 'F:/project' }; },
  };
  const imports = {
    thread: { JXB: value => value, weu: value => value.mode },
    atoms: { Qk: 'host', we: 'permissions', JN: 'cwd', h2: 'extra' },
    feature: { a: 'feature' }, adjust: { o: value => adjusted ?? value }, client: { V: () => client },
  };
  const modules = vm.runInNewContext(code.replaceAll('export const ', 'const ') + '\n;__webpack_modules__');
  const exports = {};
  modules.eYlV({}, exports, name => imports[name]);
  return exports;
}

test('webpack delegated permissions use canonical server state and preserve the destination adjustment', async () => {
  const permissions = { mode: 'full-access', activePermissionProfile: { id: ':danger-full-access' } };
  const adjusted = { mode: 'auto', activePermissionProfile: { id: ':workspace' } };
  const { output } = transformed();
  const entry = entrypoints(output.get('fixture.js'), permissions, adjusted);
  const scope = { get: atom => atom === 'feature' ? true : null };
  assert.equal((await entry.worktree(scope, 'source', 'local')).sourcePermissionSelection.permissions, permissions);
  assert.equal((await entry.local(scope, 'source', 'local', null, 'F:/project')).sourcePermissionSelection.permissions, adjusted);
  assert.equal((await entry.local(scope, 'source', 'local', 'remote')).sourcePermissionSelection, null);
});

test('webpack duplicate chunks are all patched and changed resolver layouts fail', () => {
  const result = transformed(new Map([['a.js', source], ['b.js', source]]));
  assert.equal(result.output.size, 2);
  assert.equal(result.changes[0].copies, 2);
  assert.throws(() => transformed(new Map([['a.js', source.replace('let c=(0,i.weu)(d)', 'let c=unknown(d)')]])), /helper changed/);
});
