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
const { transformWebpackPermissions, transformWebpackUsage } = loaded.exports;

const usageFixture = `export const __webpack_modules__={
target(e,t,n){let atom=(0,api.i1)(root,(thread)=>{return{activeWorkspaceRoot:null,conversationHostId:"local"}});n.d(t,{},{targetAtom:atom})},
config(e,t,n){let key=["user-saved-config"],atom=(0,api.vU)(root.scope,({cwd:dir=null,hostId:host})=>{});n.d(t,{},{configAtom:atom})},
provider(e,t,n){let atom=select(({summary:s})=>s.modelProvider||null);n.d(t,{},{threadProvider:atom})},
composer(e,t,n){
var hooks=n("qmMi"), route=n("route");
n.d(t,{ComposerContent:()=>ComposerContent});
function ComposerContent(input){let {sendBlocked:blocked}=function(opts){let threshold=1,{hostId:h,selectedModel:m,settings:s}=opts,host=void 0===h?"local":h,scope=(0,hooks.gh)(route.ctx);let active=(0,route.resolve)(scope);let thread=active,isMain="local"===scope.value.kind;
if(isMain)s.fallback();
let out={dataUpdatedAt:1,selectedModel:m,isUsageBannerEnabled:true,rateLimit:10,rateLimitWarningThreshold:threshold,sendBlocked:true},end=0;return end,out}(input),unused=0;return blocked}
},
banner(e,t,n){
n.d(t,{state:()=>state});
function state(){let account={hardBlocked:true},limit=true,banner=true,rate=10;let blocked=account.hardBlocked||limit;return {canShowUsageBanners:banner,imageGenerationLimit:null,onDismissImageGenerationLimit:null,rateLimit:rate,sendBlocked:blocked}}
},
adapter(e,t,n){
var hooks=n("qmMi"), threads=n("threads"), quota=n("a6kU");
n.d(t,{CodexComposerAdapter:()=>Adapter});
function Adapter(thread){let host=(0,hooks._U)(threads.qX,thread),reason=(0,hooks._U)(quota.o,host);return {submitDisabled:reason}}
},
capability(e,t,n){
n.d(t,{check:()=>check});
function check(request,host,provider){if(host==null)throw Error(\`Explicit-host capability requires hostId: \${request.name}\`);let checks=[];if(request.requiredRbacPermissions.length>0&&checks.push(true),request.requiresFirstPartyInference&&host==="local"){let request=provider,loading=false,error=false;checks.push({isCapable:!loading&&!error&&(request??"openai")==="openai"})}return checks[0]?.isCapable}
}
};`;

function usageEntrypoints({ provider, configuredProvider = 'openai', targetHost = 'local', thread = 'existing' }) {
  const { output } = transformWebpackUsage(new Map([['usage.js', usageFixture]]));
  const modules = vm.runInNewContext(output.get('usage.js').replace('export const ', 'const ') + '\n;__webpack_modules__');
  const imports = {
    qmMi: { _U: (read, input) => read(input), gh: () => ({ value: { kind: 'local' } }) },
    route: { resolve: () => thread },
    target: { targetAtom: () => ({ cwd: '/repo', hostId: targetHost }) },
    config: { configAtom: () => ({ data: { model_provider: configuredProvider } }) },
    provider: { threadProvider: () => provider },
    threads: { qX: () => 'local' },
    a6kU: { o: () => 'reserve-limit,usage-limit' },
  };
  const load = id => {
    const exports = {};
    const requireModule = name => imports[name];
    requireModule.d = (target, fields) => {
      for (const [name, get] of Object.entries(fields)) Object.defineProperty(target, name, { get, enumerable: true });
    };
    modules[id]({}, exports, requireModule);
    return exports;
  };
  return { ...load('composer'), ...load('banner'), ...load('adapter'), ...load('capability') };
}

test('quota blocks and automatic fallback are suppressed only for the matching codex-lb thread', () => {
  for (const [state, blocked] of [
    [{ provider: 'codex-lb' }, false],
    [{ thread: null, configuredProvider: 'codex-lb' }, false],
    [{ provider: 'openai', configuredProvider: 'codex-lb' }, true],
    [{ provider: 'codex-lb', targetHost: 'remote' }, true],
  ]) {
    const ui = usageEntrypoints(state);
    let fallbacks = 0;
    assert.equal(ui.ComposerContent({ selectedModel: 'test', settings: { fallback: () => fallbacks++ } }), blocked);
    assert.equal(fallbacks, Number(blocked));
    const banner = ui.state();
    assert.equal(banner.canShowUsageBanners, blocked);
    assert.equal(banner.sendBlocked, blocked);
    assert.equal(banner.rateLimit, blocked ? 10 : null);
    const adapterThread = state.thread === undefined ? 'existing' : state.thread;
    assert.equal(ui.CodexComposerAdapter(adapterThread).submitDisabled, blocked ? 'reserve-limit,usage-limit' : '');
  }
});

test('the first-party exception on the new layout stays limited to dictation and navigation', () => {
  const { check } = usageEntrypoints({});
  const request = name => ({ name, requiredRbacPermissions: [], requiresFirstPartyInference: true });
  assert.equal(check(request('dictation.transcribe'), 'local', 'codex-lb'), true);
  assert.equal(check(request('orbit.navigation'), 'local', 'codex-lb'), true);
  assert.equal(check(request('another-feature'), 'local', 'codex-lb'), false);
  assert.equal(check(request('another-feature'), 'local', 'openai'), true);
  assert.equal(check(request('dictation.transcribe'), 'local', 'other'), false);
});

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
