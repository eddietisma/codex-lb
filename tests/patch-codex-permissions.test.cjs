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
const { readSourcePermissionSelection, transformThreadPermissions } = loaded.exports;
const fullAccess = { approvalPolicy: 'never', sandboxPolicy: { type: 'dangerFullAccess' }, activePermissionProfile: { id: ':danger-full-access' } };
const workspace = { approvalPolicy: 'on-request', sandboxPolicy: { type: 'workspaceWrite' }, activePermissionProfile: { id: ':workspace' } };

function fixture(permissions = fullAccess) {
  const calls = [];
  const client = {
    async getThreadListSummary(id) { calls.push(['summary', id]); return { hostId: 'local' }; },
    async getCurrentPermissions(id) { calls.push(['permissions', id]); return permissions; },
    async getFollowUpContext(id) { calls.push(['context', id]); return { cwd: 'F:\\project' }; },
  };
  return {
    calls,
    args: {
      sourceHostId: null, destinationHostId: 'local', sourceThreadId: 'source', client,
      toAgentMode: value => value === fullAccess ? 'full-access' : value === workspace ? 'auto' : null,
    },
  };
}

test('missing UI state inherits verified source permissions from its owning server', async () => {
  const { calls, args } = fixture();
  assert.deepEqual(await readSourcePermissionSelection(args), {
    agentMode: 'full-access', permissions: fullAccess, permissionProfileId: ':danger-full-access', sourceCwd: 'F:\\project',
  });
  assert.deepEqual(calls, [['summary', 'source'], ['permissions', 'source'], ['context', 'source']]);
});

test('source workspace permissions remain restricted', async () => {
  const { args } = fixture(workspace);
  assert.equal((await readSourcePermissionSelection(args)).permissionProfileId, ':workspace');
});

test('known and server-reported cross-host sources cannot inherit permissions', async () => {
  const { calls, args } = fixture();
  assert.equal(await readSourcePermissionSelection({ ...args, sourceHostId: 'remote' }), null);
  assert.deepEqual(calls, []);
  args.client.getThreadListSummary = async () => ({ hostId: 'remote' });
  assert.equal(await readSourcePermissionSelection(args), null);
  assert.deepEqual(calls, []);
});

test('missing source, permissions, context and RPC failure preserve the existing fallback', async () => {
  for (const method of ['getThreadListSummary', 'getCurrentPermissions', 'getFollowUpContext']) {
    const { args } = fixture();
    args.client[method] = async () => null;
    assert.equal(await readSourcePermissionSelection(args), null, method);
  }
  const { args } = fixture();
  args.client.getCurrentPermissions = async () => { throw new Error('disconnected'); };
  assert.equal(await readSourcePermissionSelection(args), null);
  const unknown = fixture({});
  assert.equal(await readSourcePermissionSelection(unknown.args), null);
});

const source = `
async function config(scope,host){await rpc(scope,host).sendRequest(\`config/read\`)}
function inherit(scope,thread,host,sourceHost){if(thread==null)return null;let key=threadKey(thread);if(sourceHost!=null){if(sourceHost!==host)return null}else if(scope.get(hostAtom,key)!==host)return null;let permissions=scope.get(permissionAtom,key);if(permissions==null)return null;let mode=toMode(permissions);return mode==null?null:{agentMode:mode,permissions:permissions,permissionProfileId:permissions.activePermissionProfile?.id??null,sourceCwd:scope.get(cwdAtom,key)}}
function next(){}
async function local(scope,thread,host){return {sourcePermissionSelection:inherit(scope,thread,host,undefined)}}
async function worktree(scope,thread,host){return {sourcePermissionSelection:inherit(scope,thread,host,undefined)}}
`;

test('both local and worktree creation await canonical source permissions', async () => {
  const { args } = fixture();
  const transformed = transformThreadPermissions(source);
  const context = { rpc: () => args.client, threadKey: value => value, hostAtom: 'host', permissionAtom: 'permissions', cwdAtom: 'cwd', toMode: args.toAgentMode };
  const entrypoints = vm.runInNewContext(transformed.code + ';({local,worktree})', context);
  const scope = { get: () => null };
  for (const create of [entrypoints.local, entrypoints.worktree]) {
    const result = await create(scope, 'source', 'local');
    assert.equal(result.sourcePermissionSelection.agentMode, 'full-access');
  }
  assert.equal(transformed.changes.length, 1);
});

test('cloud creation skips source permission lookup while local creation awaits it', async () => {
  const { args, calls } = fixture();
  const guarded = source.replace('async function local(scope,thread,host)', 'async function local(scope,thread,host,target)')
    .replace('sourcePermissionSelection:inherit', 'sourcePermissionSelection:target.type===`codexCloud`?null:inherit');
  const transformed = transformThreadPermissions(guarded);
  const context = { rpc: () => args.client, threadKey: value => value, hostAtom: 'host', permissionAtom: 'permissions', cwdAtom: 'cwd', toMode: args.toAgentMode };
  const create = vm.runInNewContext(transformed.code + ';local', context);
  const scope = { get: () => null };
  assert.equal((await create(scope, 'source', 'local', { type: 'codexCloud' })).sourcePermissionSelection, null);
  assert.deepEqual(calls, []);
  assert.equal((await create(scope, 'source', 'local', { type: 'local' })).sourcePermissionSelection.agentMode, 'full-access');
});

test('unknown or partially matched app layouts fail before patching', () => {
  assert.throws(() => transformThreadPermissions('export {};'), /Unsupported app layout/);
  assert.throws(() => transformThreadPermissions(source.replace('sourcePermissionSelection:inherit', 'different:inherit')), /Unsupported app layout/);
  assert.throws(() => transformThreadPermissions(source.replace('let key=threadKey(thread);', 'let key=threadKey(thread);if(scope.restricted)return null;')), /Unsupported app layout/);
});
