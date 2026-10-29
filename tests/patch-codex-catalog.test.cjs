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
const { transformCatalogDiscovery } = loaded.exports;
const source = 'class Enablement{constructor(evaluations){this.evaluations=evaluations}async sendEnablement($,t){let n=await this.evaluations.readExecutionAssignments();if(n==null)return;let a={api_key_model_discovery:n.discovery,memories:false};a.codex_apps_mcp_2026_07_28=!0,a.windows_sandbox_service=!0;return $.connection.sendAppServerRequest("experimentalFeature/enablement/set",{enablement:a})}}';

function fixture(config, hostId = 'local', discovery = false) {
  const Enablement = vm.runInNewContext(transformCatalogDiscovery(source).code + ';Enablement');
  const calls = [];
  const connection = {hostId, async sendAppServerRequest(method, params) {
    calls.push({method, params});
    return method === 'config/read' ? {config} : params.enablement;
  }};
  return {calls, send: () => new Enablement({async readExecutionAssignments() { return {discovery}; }}).sendEnablement({connection},1)};
}

test('explicit local CodexLB catalog survives a disabled Desktop discovery rollout', async () => {
  const {calls, send} = fixture({model_provider:'codex-lb', model_providers:{'codex-lb':{model_catalog_url:'http://127.0.0.1:2455/backend-api/codex/models'}}});
  const enablement = await send();
  assert.deepEqual(calls.map(call => call.method), ['config/read', 'experimentalFeature/enablement/set']);
  assert.equal(enablement.api_key_model_discovery, true);
  assert.equal(enablement.memories, false);
  assert.equal(enablement.windows_sandbox_service, true);
});

test('other providers and missing or empty catalog URLs retain Desktop defaults', async () => {
  for (const config of [
    {model_provider:'openai'},
    {model_provider:'codex-lb',model_providers:{'codex-lb':{}}},
    {model_provider:'codex-lb',model_providers:{'codex-lb':{model_catalog_url:'  '}}},
    {model_provider:'other',model_providers:{other:{model_catalog_url:'https://example.invalid/models'}}},
  ]) assert.equal((await fixture(config).send()).api_key_model_discovery, false);
  assert.equal((await fixture({model_provider:'openai'},'local',true).send()).api_key_model_discovery,true);
});

test('remote servers retain their discovery settings without a config request', async () => {
  const {calls, send} = fixture({model_provider:'codex-lb',model_providers:{'codex-lb':{model_catalog_url:'http://localhost/models'}}},'remote');
  assert.equal((await send()).api_key_model_discovery,false);
  assert.deepEqual(calls.map(call => call.method),['experimentalFeature/enablement/set']);
});

test('unknown or ambiguous enablement layouts fail before patching', () => {
  assert.throws(() => transformCatalogDiscovery('export {};'), /Unsupported app layout/);
  assert.throws(() => transformCatalogDiscovery(source + source), /Unsupported app layout/);
});
