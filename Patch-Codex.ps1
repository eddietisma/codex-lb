<#
Codex-lb patch and launcher. One script; requires the Node.js already installed on this PC.
Default: detect the current Store build, prepare/reuse a patched copy, restart Codex,
and open your normal profile. Store files are not modified.
The runtime cache and shortcut icon are stored in Local AppData.
The sidebar has saved workspaces, each with an explicit list of folders.
Use All to show everything, + to add a workspace, and Folders to edit its paths.
-CheckOnly checks compatibility without writing or restarting.
-PrepareOnly prepares the runtime without closing or launching Codex.
-NoRestart refuses to launch while another Codex instance is open.
Unknown app structures stop safely. The modified runtime copy is unsigned.
#>
[CmdletBinding()]
param(
    [switch]$CheckOnly,
    [switch]$PrepareOnly,
    [switch]$NoRestart,
    [switch]$ShowErrors,
    [string]$OutputRoot,
    [string]$CodexHome = (Join-Path $env:USERPROFILE '.codex')
)
if (!$OutputRoot) { $OutputRoot = Join-Path $env:LOCALAPPDATA 'CodexProviderPatch\runtime' }
$engineCode = @'
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { spawnSync } = require('node:child_process');
const assert = require('node:assert/strict');
const { transform, transformSplit } = (() => {
'use strict';
// Structural matchers are deliberately narrow: unfamiliar layouts stop the patch.
const path = require('node:path');
const ID = '[A-Za-z_$][\\w$]*';
const helper = 'function codexLbUsesExternalUsage(provider){return provider===`codex-lb`}function codexLbBlocksWorkspaceUsage(provider,blocked){return blocked&&!codexLbUsesExternalUsage(provider)}';
const escape = value => value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
function uniqueMatches(text, regex, label) {
  const matches = [...text.matchAll(regex)];
  if (matches.length !== 1) throw new Error(`Unsupported app layout: ${label} matched ${matches.length} times. No patch applied.`);
  return matches[0];
}
function replaceOnce(text, before, after, label, changes) {
  const at = text.indexOf(before);
  if (at < 0 || text.indexOf(before, at + before.length) !== -1) throw new Error(`Ambiguous patch anchor: ${label}`);
  changes.push({ name: label, before, after });
  return text.slice(0, at) + after + text.slice(at + before.length);
}
function bindings(text, kind) {
  const clauses = kind === 'import'
    ? [...text.matchAll(/import\{([^}]+)\}from["']([^"']+)["']/g)]
    : [...text.matchAll(/export\{([^}]+)\}/g)];
  return clauses.map(match => ({
    file: match[2],
    names: match[1].split(',').map(token => {
      const parts = token.trim().split(/\s+as\s+/);
      return { local: parts.at(-1), original: parts[0] };
    }),
  }));
}
function importedSelector(source, asset, readFile, pattern, label, missingImports) {
  const results = [];
  for (const clause of bindings(source, 'import')) {
    if (!clause.file?.endsWith('.js')) continue;
    const file = path.posix.normalize(path.posix.join(path.posix.dirname(asset), clause.file));
    if (!file.startsWith('webview/assets/')) throw new Error('Unexpected import path');
    const moduleSource = readFile(file);
    const matches = [...moduleSource.matchAll(pattern)];
    for (const match of matches) {
      const exports = bindings(moduleSource, 'export').flatMap(item => item.names);
      const exported = exports.filter(item => item.original === match[1]);
      const imported = clause.names.filter(item => exported.some(entry => entry.local === item.original));
      for (const item of imported) results.push(item.local);
      if (!imported.length && missingImports) for (const item of exported) {
        const alias = 'codexLb' + label.replace(/[^a-z]/gi, '');
        missingImports.add(`import{${item.local} as ${alias}}from${JSON.stringify(clause.file)};`);
        results.push(alias);
      }
    }
  }
  const candidates = [...new Set(results)];
  if (candidates.length !== 1) throw new Error(`Unsupported app layout: cannot resolve ${label} (${candidates.length} candidates)`);
  return candidates[0];
}
function providerHelpers(source, asset, readFile, readHook) {
  const imports = new Set();
  const target = importedSelector(source, asset, readFile,
    new RegExp(`(${ID})=${ID}\\(${ID},\\(${ID},\\{get:${ID}\\}\\)=>\\{.{0,650}?return\\{activeWorkspaceRoot:`, 'g'), 'execution target atom', imports);
  const config = importedSelector(source, asset, readFile,
    new RegExp(`(${ID})=${ID}\\(${ID},\\(\\{cwd:(${ID})=null,hostId:(${ID})\\},\\{get:${ID},queryClient:${ID},scope:${ID}\\}\\)=>${ID}\\(\\{scope:${ID},queryClient:${ID},hostId:\\3,cwd:\\2,enabled:`, 'g'), 'effective config query', imports);
  const provider = importedSelector(source, asset, readFile,
    new RegExp(`(${ID})=${ID}\\(\\(\\{summary:(${ID})\\}\\)=>\\2\\.modelProvider\\|\\|null\\)`, 'g'), 'thread provider atom', imports);
  // A new remote draft has no thread ID, so its thread host still defaults to local.
  return [...imports].join('') + helper + `function codexLbExternalThread(thread,host){let target=${readHook}(${target},thread),config=${readHook}(${config},{cwd:target.cwd,hostId:thread==null?target.hostId:host}),provider=${readHook}(${provider},thread);return (thread==null||target.hostId===host)&&codexLbUsesExternalUsage(provider??config.data?.model_provider)}`;
}
function importAlias(source, symbol, destination) {
  const origin = bindings(source, 'import').flatMap(clause => clause.names.filter(name => name.local === symbol).map(name => ({ file: clause.file, name: name.original })));
  if (origin.length !== 1) throw new Error('Cannot resolve shared import: ' + symbol);
  const names = bindings(destination, 'import').filter(clause => clause.file === origin[0].file).flatMap(clause => clause.names.filter(name => name.original === origin[0].name));
  if (names.length !== 1) throw new Error('Cannot resolve destination import: ' + symbol);
  return names[0].local;
}
function transformSplit(sources, readFile) {
  const changes = [], output = new Map();
  const select = (prefix, marker) => {
    const matches = [...sources.keys()].filter(key => key.startsWith('webview/assets/' + prefix + '-') && key.endsWith('.js') && (!marker || sources.get(key).includes(marker)));
    if (matches.length !== 1) throw new Error('Expected one ' + prefix + ' bundle');
    return matches[0];
  };
  const contentAsset = select('composer-content', 'dataUpdatedAt:'), content = sources.get(contentAsset);
  const q = uniqueMatches(content, new RegExp(`function (${ID})\\((${ID})\\)\\{let (${ID})=\\(0,(${ID})\\.c\\)\\(\\d+\\),\\{hostId:(${ID}),selectedModel:(${ID})\\}=\\2,(${ID})=\\5===void 0\\?(${ID}):\\5,(${ID})=(${ID})\\((${ID})\\),`, 'g'), 'usage hook');
  const end = content.indexOf('}var ' + q[4] + ',', q.index) + 1;
  if (end <= q.index) throw new Error('Cannot locate usage hook boundary');
  let quota = content.slice(q.index, end);
  const thread = uniqueMatches(quota, new RegExp(`let (${ID})=(${ID}),${ID}=${escape(q[9])}\\.value\\.kind===`, 'g'), 'usage thread');
  const resolver = uniqueMatches(quota, new RegExp(`${escape(thread[2])}=(${ID})\\(${escape(q[9])}\\)`, 'g'), 'thread resolver')[1];
  const usage = uniqueMatches(quota, new RegExp(`\\{data:(${ID}),dataUpdatedAt:${ID}\\}=(${ID})\\((${ID})\\),(${ID})=\\2\\(${ID}\\),(${ID})=\\2\\((${ID})\\)`, 'g'), 'workspace usage atoms');
  const insertion = uniqueMatches(quota, new RegExp(`let (${ID})=${ID}\\?\\?null,${ID}=(${ID})\\(${ID},\\1\\),${ID}=\\2\\(${ID},\\1\\),`, 'g'), 'usage provider injection');
  const readHook = insertion[2];
  const tail = uniqueMatches(quota, new RegExp(`,(${ID})\\}$`, 'g'), 'usage return');
  const external = `codexLbExternalThread(${thread[1]},${q[7]})`;
  // Read provider hooks before memoized output, then override the returned value.
  quota = replaceOnce(quota, insertion[0], `let codexLbExternal=${external};` + insertion[0], 'composer usage', changes);
  quota = replaceOnce(quota, tail[0], `,codexLbExternal?{...${tail[1]},rateLimit:null,rateLimitWarningThreshold:null,isUsageBannerEnabled:!1,sendBlocked:!1}:${tail[1]}}`, 'composer usage output', changes);
  output.set(contentAsset, replaceOnce(content, content.slice(q.index, end), providerHelpers(content, contentAsset, readFile, readHook) + quota, 'usage module replacement', []));

  const primaryAsset = select('app-primary'), primary = sources.get(primaryAsset);
  const banner = uniqueMatches(primary, new RegExp(`function (${ID})\\(${ID}\\)\\{let ${ID}=\\(0,${ID}\\.c\\)\\(\\d+\\),\\{canShowUsageBanners:`, 'g'), 'usage banner');
  const bannerEnd = primary.indexOf('function ', banner.index + banner[0].length);
  let bannerCode = primary.slice(banner.index, bannerEnd);
  const guard = uniqueMatches(bannerCode, new RegExp(`(${ID})=(${ID})\\(${ID},(${ID})\\);if\\(!(${ID})\\)return (${ID});`, 'g'), 'banner guard');
  const currentThread = `${importAlias(content, resolver, primary)}(${importAlias(content, q[10], primary)}(${importAlias(content, q[11], primary)}))`;
  const bannerAfter = guard[0].slice(0, guard[0].indexOf(';') + 1) + `let codexLbExternal=codexLbExternalThread(${currentThread},${guard[3]});if(!${guard[4]}||codexLbExternal)return ${guard[5]};`;
  bannerCode = replaceOnce(bannerCode, guard[0], bannerAfter, 'usage banner', changes);
  output.set(primaryAsset, replaceOnce(primary, primary.slice(banner.index, bannerEnd), providerHelpers(primary, primaryAsset, readFile, guard[2]) + bannerCode, 'banner module replacement', []));

  const adapterAsset = select('codex-composer-adapter', 'STEPS_PROSE'), adapter = sources.get(adapterAsset);
  const quotaAtom = importAlias(content, usage[6], adapter);
  const adapterQuota = uniqueMatches(adapter, new RegExp(`(${ID})=${ID}\\(\\),(${ID})=(${ID})\\((${ID})===\x60local\x60&&${escape(quotaAtom)}\\),(${ID})=\\1===\x60STEPS_PROSE\x60\\?${ID}:null`, 'g'), 'composer adapter quota');
  const head = adapter.slice(adapter.lastIndexOf('function ', adapterQuota.index), adapterQuota.index);
  const adapterThread = uniqueMatches(head, new RegExp(`${escape(adapterQuota[4])}=(${ID})\\(${ID},(${ID})\\)`, 'g'), 'adapter thread');
  const adapterAfter = adapterQuota[0].replace(`${adapterQuota[2]}=${adapterQuota[3]}(`, `codexLbExternal=codexLbExternalThread(${adapterThread[2]},${adapterQuota[4]}),${adapterQuota[2]}=!codexLbExternal&&${adapterQuota[3]}(`);
  // The query hook must run even when codex-lb is selected.
  const safeAfter = adapterAfter.replace(`!codexLbExternal&&${adapterQuota[3]}(${adapterQuota[4]}===\x60local\x60&&${quotaAtom})`, `${adapterQuota[3]}(${adapterQuota[4]}===\x60local\x60&&${quotaAtom})&&!codexLbExternal`);
  const hostQuotaAtom = importedSelector(adapter, adapterAsset, readFile,
    new RegExp(`(${ID})=${ID}\\(${ID},\\((${ID}),\\{get:(${ID})\\}\\)=>\\3\\((${ID}),\\2\\)\\.hardBlocked\\)`, 'g'), 'host account quota');
  const hostQuota = uniqueMatches(head, new RegExp(`(${ID})=${escape(adapterThread[1])}\\(${escape(hostQuotaAtom)},${escape(adapterQuota[4])}\\)`, 'g'), 'composer host account quota');
  const submitQuota = uniqueMatches(adapter, new RegExp(`\\|\\|${escape(hostQuota[1])}\\|\\|${escape(adapterQuota[2])},`, 'g'), 'composer submit quota');
  let adapterCode = replaceOnce(adapter, adapterQuota[0], safeAfter, 'composer adapter quota', changes);
  // The host account quota also blocks remote Send independently of workspace usage.
  adapterCode = replaceOnce(adapterCode, submitQuota[0], `||(${hostQuota[1]}&&!codexLbExternal)||${adapterQuota[2]},`, 'composer submit account quota', changes);
  output.set(adapterAsset, providerHelpers(adapter, adapterAsset, readFile, adapterThread[1]) + adapterCode);

  const initialAsset = select('app-initial'), initial = sources.get(initialAsset);
  const gate = uniqueMatches(initial, new RegExp(`if\\((${ID})\\.requiresFirstPartyInference&&(${ID})\\(${ID},\x60\\d+\x60\\)\\)\\{let ${ID}=\\2\\(${ID},\\{hostId:${ID},cwd:null,failClosed:!0\\}\\),(${ID})=${ID}\\.isError,(${ID})=!\\3&&${ID}\\.data==null,(${ID})=${ID}\\.data==null\\?null:${ID}\\(${ID}\\.data\\.config\\)\\.model_provider;${ID}\\.push\\(\\{isLoading:\\4,isError:\\3,isCapable:!\\4&&!\\3&&\\(\\5\\?\\?\x60openai\x60\\)===\x60openai\x60\\}\\)\\}`, 'g'), 'capability provider gate');
  const request = uniqueMatches(initial.slice(initial.lastIndexOf('function ', gate.index), gate.index), new RegExp(`Explicit-host capability requires hostId: \\$\\{(${ID})\\.name\\}`, 'g'), 'capability request')[1];
  // Dot navigation and Dot chats share this gate with dictation.
  const gateAfter = `let codexLbProviderCapability=${request}.name===\x60dictation\x60||${request}.name.startsWith(\x60dictation.\x60)||${request}.name===\x60orbit\x60||${request}.name===\x60orbit.navigation\x60;` + gate[0].replace(`(${gate[5]}??\x60openai\x60)===\x60openai\x60`, `((${gate[5]}??\x60openai\x60)===\x60openai\x60||codexLbProviderCapability&&${gate[5]}===\x60codex-lb\x60)`);
  output.set(initialAsset, replaceOnce(initial, gate[0], gateAfter, 'dictation and dot provider', changes));
  return { output, changes };
}
function transform(source, asset, readFile) {
  if (source.includes('codexLbUsesExternalUsage')) throw new Error('Source is already patched; use the unmodified installed app.');
  const targetAtom = importedSelector(source, asset, readFile,
    new RegExp(`(${ID})=${ID}\\(${ID},\\(${ID},\\{get:${ID}\\}\\)=>\\{.{0,650}?return\\{activeWorkspaceRoot:`, 'g'), 'execution target atom');
  const configAtom = importedSelector(source, asset, readFile,
    new RegExp(`(${ID})=${ID}\\(${ID},\\(\\{cwd:(${ID})=null,hostId:(${ID})\\},\\{get:${ID},queryClient:${ID},scope:${ID}\\}\\)=>${ID}\\(\\{scope:${ID},queryClient:${ID},hostId:\\3,cwd:\\2,enabled:`, 'g'), 'effective config query');
  const providerAtom = importedSelector(source, asset, readFile,
    new RegExp(`(${ID})=${ID}\\(\\(\\{summary:(${ID})\\}\\)=>\\2\\.modelProvider\\|\\|null\\)`, 'g'), 'thread provider atom');

  const q = uniqueMatches(source,
    new RegExp(`function (${ID})\\((${ID})\\)\\{let (${ID})=\\(0,(${ID})\\.c\\)\\(\\d+\\),\\{hostId:(${ID}),selectedModel:(${ID})\\}=\\2,(${ID})=\\5===void 0\\?(${ID}):\\5,(${ID})=(${ID})\\((${ID})\\),`, 'g'), 'usage hook');
  const quotaName = q[1], memo = q[3], memoOwner = q[4], host = q[7], scope = q[9], scopeHook = q[10], scopeAtom = q[11];
  const quotaStart = q.index;
  const quotaEnd = source.indexOf('}var ' + memoOwner + ',', quotaStart) + 1;
  if (quotaEnd <= quotaStart) throw new Error('Cannot locate usage hook boundary');
  let quota = source.slice(quotaStart, quotaEnd);
  if (!quota.includes('rateLimit:') || !quota.includes('sendBlocked:')) throw new Error('Unexpected usage hook output');
  const thread = uniqueMatches(quota, new RegExp(`let (${ID})=(${ID}),${ID}=${escape(scope)}\\.value\\.kind===`, 'g'), 'usage thread');
  const threadId = thread[1];
  const resolver = uniqueMatches(quota, new RegExp(`${escape(thread[2])}=(${ID})\\(${escape(scope)}\\)`, 'g'), 'thread resolver')[1];
  const usage = uniqueMatches(quota,
    new RegExp(`\\{data:(${ID}),dataUpdatedAt:${ID}\\}=(${ID})\\((${ID})\\),(${ID})=\\2\\(${ID}\\),(${ID})=\\2\\((${ID})\\)`, 'g'), 'workspace usage atoms');
  const rate = usage[1], queryHook = usage[2], fallback = usage[4], blocked = usage[5], quotaAtom = usage[6];
  const injection = uniqueMatches(quota, new RegExp(`let ${ID}=(${ID})\\(${ID},${ID}\\),${ID};(?=${escape(memo)}\\[)`, 'g'), 'usage hook injection');
  const readHook = injection[1];
  const changes = [];
  // Resolve minified imports in module scope: component locals may shadow them.
  const providerHelpers = helper + `function codexLbReadTarget(thread){return ${readHook}(${targetAtom},thread)}function codexLbReadConfig(target,hostId){return ${readHook}(${configAtom},{cwd:target.cwd,hostId})}function codexLbReadProvider(thread){return ${readHook}(${providerAtom},thread)}function codexLbCurrentThread(){return ${resolver}(${scopeHook}(${scopeAtom}))}`;
  const quotaAfter = injection[0] + `let codexLbTarget=codexLbReadTarget(${threadId}),codexLbConfig=codexLbReadConfig(codexLbTarget,${host}),codexLbProvider=codexLbReadProvider(${threadId}),codexLbExternal=codexLbTarget.hostId===${host}&&codexLbUsesExternalUsage(codexLbProvider??codexLbConfig.data?.model_provider);if(codexLbExternal){${rate}=null;${fallback}=null;${blocked}=!1}`;
  quota = replaceOnce(quota, injection[0], quotaAfter, 'composer usage', changes);
  let patched = replaceOnce(source, source.slice(quotaStart, quotaEnd), quota, 'usage hook replacement', []);
  patched = replaceOnce(patched, q[0], providerHelpers + q[0], 'provider helpers', changes);

  const bannerMarker = uniqueMatches(patched,
    new RegExp(`function (${ID})\\(${ID}\\)\\{let ${ID}=\\(0,${ID}\\.c\\)\\(\\d+\\),\\{canShowUsageBanners:`, 'g'), 'usage banner');
  const bannerStart = bannerMarker.index;
  const bannerEnd = patched.indexOf('function ', bannerStart + bannerMarker[0].length);
  if (bannerStart < 0 || bannerEnd < 0) throw new Error('Cannot locate usage banner function');
  let banner = patched.slice(bannerStart, bannerEnd);
  const bannerName = banner.match(new RegExp(`^function (${ID})\\(`))[1];
  const early = uniqueMatches(banner,
    new RegExp(`(${ID})=${escape(readHook)}\\(${ID},(${ID})\\);if\\(!(${ID})\\)return (${ID});`, 'g'), 'banner guard');
  const bannerHost = early[2], bannerEnabled = early[3], content = early[4];
  const bannerAfter = early[0].slice(0, early[0].indexOf(';') + 1) + `let codexLbThread=codexLbCurrentThread(),codexLbTarget=codexLbReadTarget(codexLbThread),codexLbConfig=codexLbReadConfig(codexLbTarget,${bannerHost}),codexLbProvider=codexLbReadProvider(codexLbThread),codexLbExternal=codexLbTarget.hostId===${bannerHost}&&codexLbUsesExternalUsage(codexLbProvider??codexLbConfig.data?.model_provider);if(!${bannerEnabled}||codexLbExternal)return ${content};`;
  const originalBanner = banner;
  banner = replaceOnce(banner, early[0], bannerAfter, 'usage banner', changes);
  patched = replaceOnce(patched, originalBanner, banner, 'banner replacement', []);

  const adapter = uniqueMatches(patched,
    new RegExp(`(${ID})=${ID}\\(\\),(${ID})=${escape(queryHook)}\\((${ID})===\x60local\x60&&${escape(quotaAtom)}\\),(${ID})=\\1===\x60STEPS_PROSE\x60\\?${ID}:null`, 'g'), 'composer adapter quota');
  const adapterStart = patched.lastIndexOf('function ', adapter.index);
  const adapterHead = patched.slice(adapterStart, adapter.index);
  const adapterThread = uniqueMatches(adapterHead,
    new RegExp(`${escape(adapter[3])}=${escape(readHook)}\\(${ID},(${ID})\\)`, 'g'), 'adapter thread')[1];
  const adapterAfter = `${adapter[1]}=` + adapter[0].slice(adapter[0].indexOf('=') + 1, adapter[0].indexOf(',')) + `,codexLbAdapterTarget=codexLbReadTarget(${adapterThread}),codexLbAdapterConfig=codexLbReadConfig(codexLbAdapterTarget,codexLbAdapterTarget.hostId),codexLbAdapterProvider=codexLbReadProvider(${adapterThread})??codexLbAdapterConfig.data?.model_provider,${adapter[2]}=codexLbBlocksWorkspaceUsage(codexLbAdapterProvider,${queryHook}(${adapter[3]}===\x60local\x60&&${quotaAtom})),` + adapter[0].slice(adapter[0].lastIndexOf(',') + 1);
  patched = replaceOnce(patched, adapter[0], adapterAfter, 'composer adapter quota', changes);
  return {
    code: patched, changes, helpers: providerHelpers,
    symbols: { targetAtom, configAtom, providerAtom, readHook, queryHook, quotaAtom, quotaName, bannerName, scopeAtom, scopeHook, resolver, adapterThread, adapterHost: adapter[3], adapterBlocked: adapter[2] },
    fragments: { quota, banner, adapter: adapterAfter.slice(adapterAfter.indexOf(',') + 1, adapterAfter.lastIndexOf(',')) },
  };
}
return { transform, transformSplit, helper };

})();
// Keep the workspace UI and matching rules independent of minified app bindings.
function createWorkspaceFilter(react, jsx, threadAtom, projectKey, chatProjectKey, chatMetadata = () => ({})) {
  const storageKey = 'codex-lb-sidebar-workspaces-v2';
  const defaults = { workspaces: [{ name: 'RoarDB', folders: [] }, { name: 'HSB', folders: [] }], active: '' };
  const listeners = new Set(), cache = new WeakMap();
  function read() {
    try {
      const value = JSON.parse(localStorage.getItem(storageKey));
      if (Array.isArray(value?.workspaces) && value.workspaces.every(item => typeof item.name === 'string'
        && item.name.trim() && Array.isArray(item.folders) && item.folders.every(folder => typeof folder === 'string'))) {
        return { workspaces: value.workspaces, active: value.workspaces.some(item => item.name === value.active) ? value.active : '' };
      }
    } catch {}
    return defaults;
  }
  let state = read();
  function update(next) {
    state = next;
    try { localStorage.setItem(storageKey, JSON.stringify(state)); } catch {}
    for (const listener of listeners) listener();
  }
  if (typeof window !== 'undefined') window.addEventListener('storage', event => {
    if (event.key !== storageKey && event.key !== null) return;
    state = read();
    for (const listener of listeners) listener();
  });
  const subscribe = listener => { listeners.add(listener); return () => listeners.delete(listener); };
  const snapshot = () => state;
  function useWorkspace() { return react().useSyncExternalStore(subscribe, snapshot, snapshot); }
  function selectedFolders(current = state) {
    return current.active ? current.workspaces.find(item => item.name === current.active)?.folders ?? [] : null;
  }
  function normalizeFolder(value) {
    let folder = value.trim().replace(/^"|"$/g, '').replaceAll('\\', '/').replace(/^\/\/\?\//, '');
    if (/^[a-z]:/i.test(folder) || folder.startsWith('//')) folder = folder.toLowerCase();
    if (folder !== '/') folder = folder.replace(/\/+$/, '');
    return folder;
  }
  function matches(value, folders = selectedFolders()) {
    if (folders === null) return true;
    const roots = folders.map(normalizeFolder).filter(Boolean);
    const includes = value => {
      if (typeof value !== 'string') return false;
      const candidate = normalizeFolder(value);
      return roots.some(root => candidate === root || (root === '/'
        ? candidate.startsWith('/') && !candidate.startsWith('//') : candidate.startsWith(root + '/')));
    };
    // Only folder metadata participates. Names, repository URLs, and message text do not.
    const fields = ['cwd', 'path', 'rootPaths', 'sourceWorkspaceRoot', 'root', 'rootFolder', 'repoPath', 'gitRepos',
      'summary', 'pendingThreadStart', 'pendingWorktree', 'task'];
    function visit(item, depth = 0) {
      if (includes(item)) return true;
      if (!item || typeof item !== 'object' || depth > 6) return false;
      if (Array.isArray(item)) return item.some(value => visit(value, depth + 1));
      return fields.some(key => visit(item[key], depth + 1));
    }
    return visit(value);
  }
  function filterResult(data, scope) {
    const folders = selectedFolders(useWorkspace());
    // Keep the app's native pagination. Filtering must not scan the whole history.
    return filter(data, scope, folders);
  }
  function filter(data, scope, folders = selectedFolders()) {
    if (folders === null) return data;
    const selection = JSON.stringify(folders);
    const previous = cache.get(data);
    const groups = folders.length ? data.codexLbAllProjectGroups ?? [...data.orderedPinnedProjectGroups, ...data.allCodexProjectGroups] : [];
    const allowedProjects = new Set(), allowedThreads = new Set();
    for (const group of groups) {
      if (!matches(group, folders)) continue;
      allowedProjects.add(projectKey(group.projectId));
      for (const key of group.threadKeys) allowedThreads.add(key);
    }
    for (const item of folders.length ? data.chatGptProjectTargets : []) {
      const id = item.project.gizmo.id, linkedId = data.linkedLocalProjectIdByChatGptProjectId.get(id);
      if (allowedProjects.has(projectKey(linkedId)) || matches(data.codexLbLocalProjects?.[linkedId], folders)) {
        allowedProjects.add(chatProjectKey(id));
        for (const key of item.localThreadKeys ?? []) allowedThreads.add(key);
      }
    }
    const conversationByKey = new Map();
    for (const [key, item] of folders.length ? data.conversationByKey : []) {
      const allowed = item.source === 'codex'
        ? allowedThreads.has(item.threadKey) || matches(scope.get(threadAtom(), item.threadKey), folders)
        : allowedProjects.has(chatProjectKey(item.target.projectId)) || matches(item.target.conversation, folders);
      if (allowed) conversationByKey.set(key, item);
    }
    // A chat can move folders while the sidebar selector retains the same object.
    const membership = JSON.stringify([[...allowedProjects], [...conversationByKey.keys()]]);
    if (previous?.selection === selection && previous.scope === scope && previous.membership === membership) return previous.result;
    const allowed = key => allowedProjects.has(key) || conversationByKey.has(key);
    const layout = { ...data.layout };
    for (const key of ['pinnedKeys', 'projectKeys', 'chatKeys']) layout[key] = layout[key].filter(allowed);
    for (const key of ['chatAttentionStates', 'projectAttentionStates']) {
      if (layout[key] instanceof Map) layout[key] = new Map([...layout[key]].filter(([key]) => allowed(key)));
    }
    if (Array.isArray(layout.chatAttentionStates)) {
      layout.chatAttentionStates = layout.chatAttentionStates.filter((_, index) => allowed(data.layout.chatKeys[index]));
    }
    if (Array.isArray(layout.projectAttentionStates)) {
      const projects = new Set(layout.projectKeys);
      layout.projectAttentionStates = data.entries.filter(item => item.kind === 'conversation' && !item.pinned
        && projects.has(item.projectKey) && allowed(item.key)).map(item => item.attentionState);
    }
    const keepGroup = group => allowedProjects.has(projectKey(group.projectId));
    const result = { ...data, layout, conversationByKey,
      entries: data.entries.filter(item => allowed(item.key)),
      orderedPinnedProjectGroups: data.orderedPinnedProjectGroups.filter(keepGroup),
      allCodexProjectGroups: data.allCodexProjectGroups.filter(keepGroup),
      codexProjectGroups: data.codexProjectGroups.filter(keepGroup),
      chatGptProjectTargets: data.chatGptProjectTargets.filter(item => allowedProjects.has(chatProjectKey(item.project.gizmo.id))),
    };
    cache.set(data, { selection, scope, membership, result });
    return result;
  }
  function Controls() {
    const React = react(), h = jsx().jsx, current = useWorkspace();
    const [editing, setEditing] = React.useState(null), [name, setName] = React.useState('');
    const [paths, setPaths] = React.useState(''), [error, setError] = React.useState('');
    const selected = current.workspaces.find(item => item.name === current.active);
    const edit = workspace => { setEditing(workspace.name); setPaths(workspace.folders.join('\n')); setError(''); };
    const inputStyle = { minWidth: 0, width: '100%', boxSizing: 'border-box', color: 'inherit',
      background: 'transparent', border: '1px solid #8886', borderRadius: 6, padding: 6, font: 'inherit' };
    const actionStyle = { border: '1px solid #8886', borderRadius: 6, padding: '4px 8px', background: 'transparent',
      color: 'inherit', font: 'inherit', cursor: 'pointer' };
    const button = (label, active, onClick, extra = {}) => h('button', {
      type: 'button', onClick, ...extra,
      style: { flexShrink: 0, boxSizing: 'border-box', display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
        height: 24, minHeight: 0, border: active ? '1px solid var(--color-token-text-primary, CanvasText)' : '1px solid var(--border-color, #6666)', borderRadius: 999,
        padding: label === '+' ? 0 : '0 8px', width: label === '+' ? 24 : undefined,
        background: active ? 'var(--color-token-text-primary, CanvasText)' : 'transparent',
        color: active ? 'var(--color-token-bg-primary, Canvas)' : 'inherit', font: 'inherit', fontSize: 12, lineHeight: '16px', cursor: 'pointer', fontWeight: active ? 700 : 400 }, children: label,
    }, label);
    return h('div', { 'data-codex-lb-workspaces': true, style: { minWidth: 0, padding: '4px 12px', fontSize: 12, lineHeight: '16px' }, children: [
      h('div', { role: 'group', 'aria-label': 'Workspace filter',
        style: { display: 'flex', gap: 6, overflowX: 'auto', scrollbarWidth: 'none', touchAction: 'pan-x', paddingBottom: 3 },
        onWheel: event => { if (event.deltaY && !event.deltaX) event.currentTarget.scrollLeft += event.deltaY; },
        children: [button('All', !current.active, () => { update({ ...current, active: '' }); setEditing(null); }, { 'aria-pressed': !current.active }),
          ...current.workspaces.map(workspace => button(workspace.name, current.active === workspace.name, () => {
            update({ ...current, active: workspace.name });
            workspace.folders.length ? setEditing(null) : edit(workspace);
          }, { 'aria-pressed': current.active === workspace.name })),
          button('+', editing === true, () => { setEditing(editing === true ? null : true); setName(''); setError(''); },
            { 'aria-label': 'Add workspace', title: 'Add workspace' })],
      }, 'tabs'),
      selected && editing !== selected.name ? h('button', { type: 'button', onClick: () => edit(selected),
        style: { marginTop: 5, font: 'inherit', color: 'inherit', background: 'transparent', border: 0, cursor: 'pointer' },
        children: 'Folders (' + selected.folders.length + ')' }, 'folders') : null,
      editing === true ? h('form', { style: { display: 'flex', gap: 6, marginTop: 6 }, onSubmit: event => {
        event.preventDefault();
        const trimmed = name.trim();
        if (!trimmed || trimmed.toLowerCase() === 'all') return;
        const existing = current.workspaces.find(item => item.name.toLowerCase() === trimmed.toLowerCase());
        const workspace = existing ?? { name: trimmed, folders: [] };
        update({ workspaces: existing ? current.workspaces : [...current.workspaces, workspace], active: workspace.name });
        setName(''); edit(workspace);
      }, children: [h('input', { autoFocus: true, 'aria-label': 'Workspace name', placeholder: 'Workspace name',
        value: name, maxLength: 80, onChange: event => setName(event.target.value),
        onKeyDown: event => { if (event.key === 'Escape') setEditing(null); }, style: inputStyle,
      }, 'name'), h('button', { type: 'submit', style: actionStyle, children: 'Add' }, 'add'),
      ] }, 'new') : null,
      typeof editing === 'string' ? h('form', { style: { marginTop: 6 }, onSubmit: event => {
        event.preventDefault();
        const folders = [...new Set(paths.split(/\r?\n/).map(value => value.trim().replace(/^"|"$/g, '')).filter(Boolean))];
        if (folders.some(folder => !/^(?:[a-z]:(?:[\\/]|$)|[\\/])/i.test(folder))) {
          setError('Use full folder paths, such as F:\\HSB.'); return;
        }
        update({ ...current, workspaces: current.workspaces.map(item => item.name === editing ? { ...item, folders } : item) });
        setEditing(null); setError('');
      }, children: [h('label', { style: { display: 'block', fontSize: 12, marginBottom: 5 }, children: [
        h('span', { children: 'Folders for ' + editing }, 'title'),
        h('textarea', { autoFocus: true, rows: 5, 'aria-label': 'Workspace folders', value: paths,
          placeholder: 'F:\\HSB\nF:\\PLAT-387\nF:\\PLAT-370', onChange: event => setPaths(event.target.value),
          style: { ...inputStyle, display: 'block', resize: 'vertical', marginTop: 5 },
        }, 'paths'),
      ] }, 'label'), h('div', { style: { fontSize: 12, opacity: 0.7, marginBottom: 6 },
        children: 'One folder per line. Includes subfolders.' }, 'hint'),
        error ? h('div', { role: 'alert', children: error }, 'error') : null,
        h('div', { style: { display: 'flex', flexWrap: 'wrap', gap: 8 }, children: [h('button', { type: 'submit', style: actionStyle, children: 'Save' }, 'save'),
          h('button', { type: 'button', style: actionStyle, onClick: () => setEditing(null), children: 'Cancel' }, 'cancel'),
          h('button', { type: 'button', style: actionStyle, 'aria-label': 'Remove workspace ' + editing, onClick: () => {
            update({ workspaces: current.workspaces.filter(item => item.name !== editing), active: '' }); setEditing(null);
          }, children: 'Remove workspace' }, 'remove')],
        }, 'actions')],
      }, 'edit') : null,
    ] });
  }
  function withControls(props) {
    const h = jsx().jsx;
    const topContent = react().useMemo(() => h(react().Fragment, { children: [h(Controls, {}, 'workspaces'),
      h(react().Fragment, { children: props.topContent }, 'original')] }), [props.topContent]);
    return { ...props, topContent };
  }
  function filterNative(data, scope) {
    const folders = selectedFolders(useWorkspace());
    const projectGroups = folders === null ? data.projectGroups : folders.length ? data.projectGroups.filter(group => matches(group, folders)) : [];
    const allowedThreads = new Set(folders?.length ? projectGroups.flatMap(group => group.threadKeys) : []);
    const threadKeys = folders?.length ? [...new Set(['threadKeys', 'chatSectionThreadKeys', 'pinnedProjectThreadKeys', 'navigationThreadKeys', 'shortcutThreadKeys']
      .flatMap(key => data[key] ?? []).concat(data.projectGroups.flatMap(group => group.threadKeys),
        data.connectionGroups?.flatMap(group => group.threadKeys) ?? []))] : [];
    const matchingThreads = new Set(threadKeys.filter(key => allowedThreads.has(key) || matches(scope.get(threadAtom(), key), folders)));
    const membership = JSON.stringify([projectGroups.map(group => group.projectId), [...matchingThreads]]);
    return react().useMemo(() => {
      if (folders === null) return data;
      const allowed = key => matchingThreads.has(key);
      const result = { ...data, projectGroups };
      for (const key of ['threadKeys', 'chatSectionThreadKeys', 'pinnedProjectThreadKeys', 'navigationThreadKeys', 'shortcutThreadKeys']) {
        if (data[key]) result[key] = data[key].filter(allowed);
      }
      if (data.connectionGroups) result.connectionGroups = data.connectionGroups.map(group => ({ ...group,
        threadKeys: group.threadKeys.filter(allowed),
      })).filter(group => group.threadKeys.length);
      return result;
    }, [data, scope, folders, membership]);
  }
  function filterPriority(items, scope) {
    const folders = selectedFolders(useWorkspace());
    function allowed(item) {
      if (!folders?.length) return folders === null;
      if (item.kind === 'task') return matches(item.threadEntry, folders) || matches(item.projectGroup, folders)
        || matches(scope.get(threadAtom(), item.threadEntry.key), folders);
      const metadata = chatMetadata(scope, item);
      return matches(item.conversation, folders) || matches(metadata.localProjects, folders);
    }
    const membership = folders === null || items == null ? '' : JSON.stringify(items.map(item =>
      item.items ? item.items.map(allowed) : allowed(item)));
    return react().useMemo(() => {
      if (folders === null || items == null) return items;
      return items.flatMap(item => {
        if (!item.items) return allowed(item) ? [item] : [];
        const visible = item.items.filter(allowed);
        return visible.length ? [{ ...item, items: visible }] : [];
      });
    }, [items, scope, folders, membership]);
  }
  return { filterResult, filter, filterNative, filterPriority, matches, withControls, Controls,
    active: () => JSON.stringify([state.active, selectedFolders()]) };
}
function transformWorkspaces(source) {
  const changes = [], ID = '[A-Za-z_$][\\w$]*';
  function one(pattern, label) {
    const found = [...source.matchAll(pattern)];
    assert.equal(found.length, 1, 'Unsupported app layout: ' + label);
    return found[0];
  }
  const selector = one(new RegExp(`(${ID})=(${ID})\\((${ID}),(${ID})\\),\\{orderedPinnedProjectGroups:`, 'g'), 'unified sidebar selector');
  const start = source.lastIndexOf('function ', selector.index);
  const scope = source.slice(start, selector.index).match(new RegExp(`(${ID})=(${ID})\\((${ID})\\),\\{accountId:`));
  assert(scope, 'Unsupported app layout: sidebar scope');
  const scopeCallPattern = scope[2].replaceAll('$', '\\$') + '\\(' + scope[3].replaceAll('$', '\\$') + '\\)';
  const sidebar = source.slice(start, selector.index);
  const navigation = one(new RegExp(`let (${ID})=${ID}\\.get\\((${ID}),${ID}\\.threadKey\\);${ID}\\(${ID},${ID}\\.threadKey,`, 'g'), 'sidebar thread metadata');
  const project = one(new RegExp(`for\\(let (${ID}) of ${ID}\\?\\[\\.\\.\\.${ID},\\.\\.\\.${ID}\\]:\\[\\]\\)${ID}\\.set\\((${ID})\\(\\1\\.projectId\\),\\{source:\x60codex\x60,group:\\1\\}\\);for\\(let (${ID}) of ${ID}\\)${ID}\\.set\\((${ID})\\(\\3\\.project\\.gizmo\\.id\\)`, 'g'), 'sidebar project keys');
  const container = one(new RegExp(`function (${ID})\\((${ID})\\)\\{let ${ID}=\\(0,${ID}\\.c\\)\\(\\d+\\),\\{activeThreadKey:${ID},activeThreadIsPinned:${ID},handleSidebarScroll:`, 'g'), 'sidebar container');
  const containerStart = source.indexOf('}var ', container.index);
  const containerCode = source.slice(container.index, containerStart);
  const reactOwner = containerCode.match(new RegExp(`\\(0,(${ID})\\.useRef\\)`))?.[1];
  assert(reactOwner, 'Unsupported app layout: sidebar React');
  const reactFactory = one(new RegExp(`${reactOwner}=(${ID})\\(\\)`, 'g'), 'sidebar React factory')[1];
  const jsxOwner = containerCode.match(new RegExp(`\\(0,(${ID})\\.jsx\\)`))?.[1];
  assert(jsxOwner, 'Unsupported app layout: sidebar JSX');
  const jsxFactory = one(new RegExp(`${jsxOwner}=(${ID})\\(\\)`, 'g'), 'sidebar JSX factory')[1];
  const before = selector[0], after = `${selector[1]}=codexLbWorkspace.filterResult(${selector[2]}(${selector[3]},${selector[4]}),${scope[1]}),{orderedPinnedProjectGroups:`;
  source = source.replace(before, after);
  changes.push({ name: 'workspace sidebar filtering', before, after });
  const containerAfter = container[0].replace('{let ', `{${container[2]}=codexLbWorkspace.withControls(${container[2]});let `);
  source = source.replace(container[0], containerAfter);
  changes.push({ name: 'workspace sidebar tabs', before: container[0], after: containerAfter });
  const sidebarAt = source.lastIndexOf('function ', source.indexOf('codexLbWorkspace.filterResult('));
  const sidebarEnd = source.indexOf('}function ', sidebarAt) + 1;
  const originalSidebar = source.slice(sidebarAt, sidebarEnd);
  // Unread retention and deferred project state belong to the selected workspace.
  source = source.replace(originalSidebar, originalSidebar.replaceAll('JSON.stringify([', 'JSON.stringify([codexLbWorkspace.active(),'));
  // Both sidebar parents use this native list for connection groups and shortcuts.
  const sidebarBody = source.slice(start, source.indexOf('}function ', selector.index));
  const connectionOwner = sidebarBody.match(new RegExp(`(${ID})\\.connectionGroups`))?.[1];
  const connection = sidebar.match(new RegExp(`(${connectionOwner})=${selector[2]}\\((${ID}),${ID}\\)`));
  assert(connection, 'Unsupported app layout: native sidebar selector');
  const calls = [...source.matchAll(new RegExp(`(${ID})=${selector[2]}\\(${connection[2]},(${ID}|\x60codex\x60)\\)`, 'g'))];
  assert.equal(calls.length, 3, 'Unsupported app layout: native sidebar parents');
  for (const call of calls) {
    const at = source.indexOf(call[0]);
    const functionAt = source.lastIndexOf('function ', at), head = source.slice(functionAt, at);
    let parentScope = head.match(new RegExp('(' + ID + ')=' + scopeCallPattern))?.[1];
    if (!parentScope) {
      parentScope = 'codexLbPriorityScope';
      const brace = source.indexOf('{', functionAt);
      source = source.slice(0, brace + 1) + `let ${parentScope}=${scope[2]}(${scope[3]});` + source.slice(brace + 1);
    }
    source = source.replace(call[0], `${call[1]}=codexLbWorkspace.filterNative(${selector[2]}(${connection[2]},${call[2]}),${parentScope})`);
  }
  const priority = one(new RegExp(`${ID}=${selector[2]}\\((${ID}),(${ID})\\),${ID}=${ID}\\(${ID}\\)\\?\\?!0,${ID}=${ID}\\(${ID}\\),${ID}=${selector[2]}\\((${ID}),\\2\\),${ID}=${selector[2]}\\((${ID}),\\2\\)`, 'g'), 'priority sidebar lists');
  const shortcuts = one(new RegExp(`(${ID})=${selector[2]}\\((${ID}),${ID}\\);if\\(!${ID}\\|\\|\\1==null\\)return null`, 'g'), 'priority sidebar shortcuts');
  const priorityCalls = [...source.matchAll(new RegExp(`${selector[2]}\\((${[priority[1], priority[3], priority[4], shortcuts[2]].join('|')}),(${ID}|\x60codex\x60)\\)`, 'g'))];
  assert.equal(priorityCalls.length, 9, 'Unsupported app layout: priority sidebar consumers');
  for (let index = priorityCalls.length - 1; index >= 0; index--) {
    const call = priorityCalls[index];
    source = source.slice(0, call.index) + `codexLbPriorityCall${index}` + source.slice(call.index + call[0].length);
  }
  for (const [index, call] of priorityCalls.entries()) {
    const placeholder = `codexLbPriorityCall${index}`;
    const at = source.indexOf(placeholder), functionAt = source.lastIndexOf('function ', at);
    let parentScope = source.slice(functionAt, at).match(new RegExp('(' + ID + ')=' + scopeCallPattern))?.[1];
    if (!parentScope) {
      parentScope = 'codexLbPriorityScope';
      const brace = source.indexOf('{', functionAt);
      source = source.slice(0, brace + 1) + `let ${parentScope}=${scope[2]}(${scope[3]});` + source.slice(brace + 1);
    }
    source = source.replace(placeholder, `codexLbWorkspace.filterPriority(${call[0]},${parentScope})`);
  }
  const localReads = [...source.matchAll(new RegExp(`(${ID})\\(${ID}\\.get,(${ID})\\.LOCAL_PROJECTS\\)`, 'g'))];
  const localBindings = [...new Set(localReads.map(match => `${match[1]}|${match[2]}`))];
  assert.equal(localBindings.length, 1, 'Unsupported app layout: configured local projects');
  const [localRead, configKeys] = localBindings[0].split('|');
  const chatAtoms = [...source.matchAll(new RegExp(`(${ID})=${selector[2]}\\((${ID}),${ID}\\),${ID}=${selector[2]}\\((${ID}),${ID}\\?\\?\\1\\?\\?null\\)`, 'g'))];
  const chatBindings = [...new Set(chatAtoms.map(match => `${match[2]}|${match[3]}`))];
  assert.equal(chatBindings.length, 1, 'Unsupported app layout: ChatGPT project metadata');
  const [conversationProject, projectAtom] = chatBindings[0].split('|');
  const metadata = `(scope,item)=>{let id=item.conversation?.gizmo_id??scope.get(${conversationProject},item.conversation?.id??item.conversationId);return{project:id==null?null:scope.get(${projectAtom},id),localProjects:id==null?[]:Object.values(${localRead}(scope.get,${configKeys}.LOCAL_PROJECTS)??{}).filter(project=>project.chatGptBacking?.projectId===id)}}`;
  const helper = `const codexLbWorkspace=(${createWorkspaceFilter.toString()})(()=>${reactFactory}(),()=>${jsxFactory}(),()=>${navigation[2]},id=>${project[2]}(id),id=>${project[4]}(id),${metadata});`;
  changes.push({ name: 'workspace priority filtering', before: priority[0], after: 'workspace-filtered priority lists and shortcuts' });
  return { code: helper + source, changes };
}
function transformWorkspaceMetadata(source) {
  const ID = '[A-Za-z_$][\\w$]*';
  const metadata = [...source.matchAll(new RegExp(`localProjects:(${ID}),resolvedProjectsWithThreads:\\[\\.\\.\\.(${ID}),\\.\\.\\.(${ID})\\.projectGroups\\]`, 'g'))];
  assert.equal(metadata.length, 1, 'Unsupported app layout: workspace repository metadata');
  const before = 'orderedPinnedProjectGroups:';
  assert.equal(source.split(before).length, 2, 'Unsupported app layout: workspace project result');
  const after = `codexLbLocalProjects:${metadata[0][1]},codexLbAllProjectGroups:[...${metadata[0][2]},...${metadata[0][3]}.projectGroups],` + before;
  return { code: source.replace(before, after), changes: [{ name: 'workspace repository metadata', before, after }] };
}
async function readSourcePermissionSelection({ sourceHostId, destinationHostId, sourceThreadId, client, toAgentMode }) {
  if (sourceHostId != null && sourceHostId !== destinationHostId) return null;
  try {
    const summary = await client.getThreadListSummary(sourceThreadId);
    if (summary?.hostId !== destinationHostId) return null;
    const permissions = await client.getCurrentPermissions(sourceThreadId);
    if (permissions == null) return null;
    const agentMode = toAgentMode(permissions);
    if (agentMode == null) return null;
    const context = await client.getFollowUpContext(sourceThreadId);
    if (context?.cwd == null) return null;
    return { agentMode, permissions, permissionProfileId: permissions.activePermissionProfile?.id ?? null, sourceCwd: context.cwd };
  } catch {
    // An unavailable or unverifiable source keeps the app's existing conservative fallback.
    return null;
  }
}
'use strict';

function webpackModules(sources) {
  const vm = require('node:vm'), result = [];
  for (const [asset, source] of sources) {
    if (!source.includes('export const __webpack_modules__=') || !['return{activeWorkspaceRoot:', '"user-saved-config"', '.modelProvider||null', 'ComposerContent:', 'canShowUsageBanners:', 'CodexComposerAdapter:', 'Explicit-host capability requires hostId:'].some(marker => source.includes(marker))) continue;
    const modules = vm.runInNewContext(source.replaceAll('export const ', 'const ') + '\n;__webpack_modules__', Object.create(null), { timeout: 2000 });
    for (const [id, fn] of Object.entries(modules)) {
      const code = Function.prototype.toString.call(fn);
      const signature = code.match(/^[\w$]+\(([^)]*)\)\{/);
      if (!signature || !source.includes(code)) throw new Error('Unsupported webpack module: ' + id);
      result.push({ asset, id, source: code, args: signature[1].split(','), body: code.slice(signature[0].length, -1) });
    }
  }
  return result;
}

function transformWebpackUsage(sources) {
  const ID = '[A-Za-z_$][\\w$]*', entries = webpackModules(sources), output = new Map(), changes = [];
  const escape = value => value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const one = (code, regex, label) => {
    const matches = [...code.matchAll(regex)];
    if (matches.length !== 1) throw new Error('Unsupported webpack usage layout: ' + label + ' matched ' + matches.length + ' times');
    return matches[0];
  };
  const select = (predicate, label) => {
    const matches = entries.filter(predicate), ids = new Set(matches.map(entry => entry.id));
    if (ids.size !== 1) throw new Error('Unsupported webpack usage module: ' + label + ' matched ' + ids.size + ' IDs');
    return matches;
  };
  const exported = (entry, symbol, label) => one(entry.source, new RegExp(`(?:[,{])(${ID}):(?:\\(\\)=>)?${escape(symbol)}(?=[,}])`, 'g'), label)[1];
  const target = select(entry => entry.source.includes('return{activeWorkspaceRoot:') && entry.source.includes('conversationHostId:'), 'execution target')[0];
  const config = select(entry => entry.source.includes('"user-saved-config"') && entry.source.includes('failClosed') === false && /\(\{cwd:\w+=null,hostId:/.test(entry.source), 'effective config')[0];
  const provider = select(entry => entry.source.includes('.modelProvider||null'), 'thread provider')[0];
  const targetSymbol = one(target.source, new RegExp(`let (${ID})=\\(0,${ID}\\.i1\\)\\(.{0,750}?return\\{activeWorkspaceRoot:`, 'g'), 'target atom')[1];
  const configSymbol = one(config.source, new RegExp(`let (${ID})=\\(0,${ID}\\.vU\\)\\(${ID}\\.${ID},\\(\\{cwd:`, 'g'), 'config atom')[1];
  const providerSymbol = one(provider.source, new RegExp(`(${ID})=${ID}\\(\\(\\{summary:(${ID})\\}\\)=>\\2\\.modelProvider\\|\\|null\\)`, 'g'), 'provider atom')[1];
  const refs = {
    target: [target.id, exported(target, targetSymbol, 'target export')],
    config: [config.id, exported(config, configSymbol, 'config export')],
    provider: [provider.id, exported(provider, providerSymbol, 'provider export')],
  };
  const composer = select(entry => entry.source.includes('dataUpdatedAt:') && entry.source.includes('isUsageBannerEnabled:') && entry.source.includes('rateLimitWarningThreshold:') && entry.source.includes('selectedModel:') && entry.source.includes('ComposerContent:'), 'composer');
  const quotaHead = one(composer[0].source, new RegExp(`sendBlocked:${ID}\\}=function\\((${ID})\\)\\{let .{0,100}?\\{hostId:(${ID}),selectedModel:(${ID})\\}=\\1,(${ID})=void 0===\\2\\?"local":\\2,(${ID})=\\(0,(${ID})\\.gh\\)\\((${ID})\\.(${ID})\\);`, 'g'), 'usage hook');
  const scopeAlias = quotaHead[7];
  const scopeModule = one(composer[0].source, new RegExp(`${escape(scopeAlias)}=${escape(composer[0].args[2])}\\("([^"]+)"\\)`, 'g'), 'scope module')[1];
  const scopeResolver = one(composer[0].source.slice(quotaHead.index, quotaHead.index + 700), new RegExp(`\\(0,${escape(scopeAlias)}\\.(${ID})\\)\\(${escape(quotaHead[5])}\\)`, 'g'), 'thread resolver')[1];
  const helpers = entry => {
    const req = entry.args[2];
    if (!req) throw new Error('Missing webpack require');
    const ref = ([id, key]) => `${req}(${JSON.stringify(id)})[${JSON.stringify(key)}]`;
    return `function codexLbExternalThread(thread,host){let read=${req}("zTeN")._U,target=read(${ref(refs.target)},thread),config=read(${ref(refs.config)},{cwd:target.cwd,hostId:thread==null?target.hostId:host}),provider=read(${ref(refs.provider)},thread);return (thread==null||target.hostId===host)&&(provider??config.data?.model_provider)==="codex-lb"}function codexLbCurrentThread(){return ${req}(${JSON.stringify(scopeModule)})[${JSON.stringify(scopeResolver)}](${req}("zTeN").gh(${req}(${JSON.stringify(scopeModule)})[${JSON.stringify(quotaHead[8])}]))}`;
  };
  const patch = (entry, edits, injectHelpers = true) => {
    let code = entry.source;
    if (code.includes('codexLbExternalThread')) throw new Error('Source already patched');
    for (const { before, after, name } of edits) {
      const index = code.indexOf(before);
      if (index < 0 || code.indexOf(before, index + before.length) >= 0) throw new Error('Ambiguous webpack patch anchor: ' + name);
      code = code.slice(0, index) + after + code.slice(index + before.length);
      changes.push({ name, asset: entry.asset, module: entry.id, before, after });
    }
    if (injectHelpers) code = code.replace('{', '{' + helpers(entry));
    const full = output.get(entry.asset) ?? sources.get(entry.asset);
    if (full.indexOf(entry.source) !== full.lastIndexOf(entry.source)) throw new Error('Duplicate webpack module source');
    output.set(entry.asset, full.replace(entry.source, () => code));
  };
  for (const entry of composer) {
    const head = one(entry.source, new RegExp(`sendBlocked:${ID}\\}=function\\((${ID})\\)\\{let .{0,100}?\\{hostId:(${ID}),selectedModel:(${ID})\\}=\\1,(${ID})=void 0===\\2\\?"local":\\2,(${ID})=\\(0,(${ID})\\.gh\\)\\((${ID})\\.(${ID})\\);`, 'g'), 'composer usage hook');
    const end = one(entry.source.slice(head.index), new RegExp(`rateLimitWarningThreshold:(${ID}),sendBlocked:(${ID})\\},.{0,350}?,(${ID})\\}\\((${ID})\\),`, 'g'), 'usage hook output');
    const hook = entry.source.slice(head.index, head.index + end.index + end[0].length);
    const thread = one(hook, new RegExp(`let (${ID})=(${ID}),${ID}="local"===${escape(head[5])}\\.value\\.kind`, 'g'), 'usage thread')[1];
    const injection = one(hook, new RegExp(`let (${ID})=${ID}\\?\\?null,${ID}=\\(0,${ID}\\._U\\)\\(`, 'g'), 'usage provider hook insertion');
    const tail = `,${end[3]}}(${end[4]}),`;
    patch(entry, [
      { name: 'composer usage provider', before: injection[0], after: `let codexLbExternal=codexLbExternalThread(${thread},${head[4]});` + injection[0] },
      { name: 'composer usage output', before: tail, after: `,codexLbExternal?{...${end[3]},rateLimit:null,rateLimitWarningThreshold:null,isUsageBannerEnabled:!1,sendBlocked:!1}:${end[3]}}(${end[4]}),` },
    ]);
  }
  const banners = select(entry => /\{canShowUsageBanners:[^}]{0,500}lowerPriorityContent:[^}]{0,300}\}=/.test(entry.source), 'usage banner');
  for (const entry of banners) {
    const guard = one(entry.source, new RegExp(`(${ID})=\\(0,(${ID})\\._U\\)\\(${ID}\\.${ID},(${ID})\\);if\\(!(${ID})\\)return (${ID});`, 'g'), 'banner guard');
    patch(entry, [{ name: 'usage banner', before: guard[0], after: guard[0].slice(0, guard[0].indexOf(';') + 1) + `let codexLbExternal=codexLbExternalThread(codexLbCurrentThread(),${guard[3]});if(!${guard[4]}||codexLbExternal)return ${guard[5]};` }]);
  }
  const adapters = select(entry => entry.source.includes('CodexComposerAdapter:') && entry.source.includes('submitDisabled:'), 'composer adapter');
  for (const entry of adapters) {
    const quotaAlias = one(entry.source, new RegExp(`(${ID})=${escape(entry.args[2])}\\("a6kU"\\)`, 'g'), 'adapter workspace quota import')[1];
    const hostQuotaAlias = one(entry.source, new RegExp(`(${ID})=${escape(entry.args[2])}\\("eLmE"\\)`, 'g'), 'adapter account quota import')[1];
    const quota = one(entry.source, new RegExp(`(${ID})=\\(0,(${ID})\\.Ul\\)\\("local"===(${ID})&&${escape(quotaAlias)}\\.U\\)`, 'g'), 'adapter quota');
    const hostQuota = one(entry.source, new RegExp(`(${ID})=\\(0,${escape(quota[2])}\\._U\\)\\(${escape(hostQuotaAlias)}\\.F9,${escape(quota[3])}\\)`, 'g'), 'adapter account quota');
    const thread = one(entry.source, new RegExp(`${escape(quota[3])}=\\(0,${escape(quota[2])}\\._U\\)\\(${ID}\\.qX,(${ID})\\)`, 'g'), 'adapter thread')[1];
    const submit = one(entry.source, new RegExp(`\\|\\|${escape(hostQuota[1])}\\|\\|${escape(quota[1])};`, 'g'), 'adapter submit quota');
    patch(entry, [
      { name: 'composer adapter quota', before: quota[0], after: `codexLbExternal=codexLbExternalThread(${thread},${quota[3]}),` + quota[0] + '&&!codexLbExternal' },
      { name: 'composer account quota', before: submit[0], after: `||(${hostQuota[1]}&&!codexLbExternal)||${quota[1]};` },
    ]);
  }
  const capabilities = select(entry => entry.source.includes('requiresFirstPartyInference&&') && entry.source.includes('Explicit-host capability requires hostId:'), 'capability provider gate');
  for (const entry of capabilities) {
    const gate = one(entry.source, new RegExp(`if\\((${ID})\\.requiresFirstPartyInference&&.{0,600}?isCapable:!(${ID})&&!(${ID})&&\\((${ID})\\?\\?"openai"\\)==="openai"\\}\\)\\}`, 'g'), 'capability gate');
    const request = one(entry.source, new RegExp('Explicit-host capability requires hostId: \\$\\{(' + ID + ')\\.name\\}', 'g'), 'capability request')[1];
    const comparison = `(${gate[4]}??"openai")==="openai"`;
    const allowed = `(${request}.name==="dictation"||${request}.name.startsWith("dictation.")||${request}.name==="orbit"||${request}.name==="orbit.navigation")`;
    // The block declares its own request-name variable in this build. Capture
    // the outer request before entering it to avoid shadowing that variable.
    patch(entry, [{ name: 'dictation and dot provider', before: gate[0], after: `let codexLbProviderCapability=${allowed};` + gate[0].replace(comparison, `(${comparison}||codexLbProviderCapability&&${gate[4]}==="codex-lb")`) }], false);
  }
  return { output, changes };
}
function transformWebpackWorkspaces(sources) {
  const assert = require('node:assert/strict'), vm = require('node:vm');
  const output = new Map(), changes = [], modules = [];
  for (const [file, source] of sources) {
    if (!source.includes('export const __webpack_modules__=') || !source.includes('orderedPinnedProjectGroups:')) continue;
    const table = vm.runInNewContext(source.replaceAll('export const ', 'const ') + '\n;__webpack_modules__', Object.create(null), { timeout: 1000 });
    for (const [id, fn] of Object.entries(table)) modules.push({ file, id, code: fn.toString() });
  }
  const unique = (items, label) => { assert.equal(items.length, 1, 'Unsupported app layout: ' + label); return items[0]; };
  const sidebar = unique(modules.filter(item => item.code.includes('{orderedPinnedProjectGroups:') && item.code.includes('activeThreadIsPinned:')), 'webpack sidebar');
  const metadata = unique(modules.filter(item => item.code.includes('localProjects:') && item.code.includes('resolvedProjectsWithThreads:[') && item.code.includes('orderedPinnedProjectGroups:')), 'webpack workspace metadata');
  const ID = '[A-Za-z_$][\\w$]*', esc = value => value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  let code = sidebar.code;
  const one = (pattern, label) => unique([...code.matchAll(pattern)], label);
  const requireName = code.match(/^[^(]+\([^,]+,[^,]+,([^,)]+)\)/)[1];
  const imported = id => one(new RegExp(`(${ID})=${esc(requireName)}\\("${id}"\\)`, 'g'), 'sidebar import ' + id)[1];
  const React = imported('zd8w'), jsx = imported('ABep'), atoms = imported('zTeN'), root = imported('OWtl');
  const projects = imported('FHI1'), threads = imported('r6TF'), native = imported('DZgh'), priority = imported('Gjlg');
  const scopeCall = `(0,${atoms}.gh)(${root}.u)`;
  const selector = one(new RegExp(`(${ID})=\\(0,${esc(atoms)}\\._U\\)\\((${ID})\\.(${ID}),(${ID})\\),\\{orderedPinnedProjectGroups:`, 'g'), 'unified sidebar selector');
  const scope = 'codexLbWorkspaceScope';
  function wrapCalls(pattern, expected, method, label) {
    const found = [...code.matchAll(pattern)];
    assert.equal(found.length, expected, 'Unsupported app layout: ' + label);
    const functions = new Set();
    for (const match of [...found].reverse()) {
      const at = code.lastIndexOf('function ', match.index), head = code.slice(at, code.indexOf('{', at) + 1);
      assert(/^function [\w$]+\([^)]*\)\{$/.test(head), 'Unsupported app layout: ' + label + ' component');
      functions.add(head);
      code = code.slice(0, match.index) + `codexLbWorkspace.${method}(${match[0]},${scope})` + code.slice(match.index + match[0].length);
    }
    for (const head of functions) {
      if (!code.includes(head + `let ${scope}=`)) code = code.replace(head, head + `let ${scope}=${scopeCall};`);
    }
    changes.push({ name: label, before: found.map(item => item[0]).join(';'), after: `${expected} workspace-filtered reads` });
  }
  wrapCalls(new RegExp(`\\(0,${esc(atoms)}\\._U\\)\\(${esc(selector[2])}\\.${esc(selector[3])},${esc(selector[4])}\\)`, 'g'), 1, 'filterResult', 'workspace sidebar filtering');
  wrapCalls(new RegExp(`\\(0,${esc(atoms)}\\._U\\)\\(${esc(native)}\\.sS,(${ID}|"codex")\\)`, 'g'), 2, 'filterNative', 'workspace native sidebar filtering');
  wrapCalls(new RegExp(`\\(0,${esc(atoms)}\\._U\\)\\(${esc(priority)}\\.(Be|p1|Vr|jU),(${ID}|"codex")\\)`, 'g'), 6, 'filterPriority', 'workspace priority filtering');
  const unifiedAt = code.indexOf('codexLbWorkspace.filterResult('), unifiedStart = code.lastIndexOf('function ', unifiedAt), unifiedEnd = code.indexOf('}function ', unifiedAt) + 1;
  assert(unifiedEnd > unifiedAt, 'Unsupported app layout: unified sidebar boundary');
  let unified = code.slice(unifiedStart, unifiedEnd);
  // Workspace changes must also invalidate compiler-cached retention boundaries.
  unified = unified.replaceAll('JSON.stringify([', 'JSON.stringify([codexLbWorkspace.active(),');
  code = code.slice(0, unifiedStart) + unified + code.slice(unifiedEnd);
  const container = one(new RegExp(`function (${ID})\\((${ID})\\)\\{let ${ID}(?:,${ID})*=\\(0,${ID}\\.c\\)\\(\\d+\\),\\{activeThreadKey:${ID},activeThreadIsPinned:`, 'g'), 'native sidebar container');
  code = code.replace(container[0], container[0].replace('{let ', `{${container[2]}=codexLbWorkspace.withControls(${container[2]});let `));
  changes.push({ name: 'workspace sidebar tabs', before: container[0], after: 'workspace controls in shared sidebar container' });
  const metadataCallback = `(scope,item)=>{let id=item.conversation?.gizmo_id??scope.get(${requireName}("MrGp").zn,item.conversation?.id??item.conversationId);return{localProjects:id==null?[]:Object.values(${requireName}("Wbxh").F6(scope.get,${requireName}("DBCl").Q2Y.LOCAL_PROJECTS)??{}).filter(project=>project.chatGptBacking?.projectId===id)}}`;
  const helper = `const codexLbWorkspace=(${createWorkspaceFilter.toString()})(()=>${React},()=>${jsx},()=>${threads}.hQ,id=>${projects}.eZ(id),id=>${projects}.ky(id),${metadataCallback});`;
  // Custom sections were added upstream. Apply the same membership rule to their rows.
  const custom = `const codexLbWorkspaceBaseFilter=codexLbWorkspace.filterResult,codexLbWorkspaceSections=new WeakMap;codexLbWorkspace.filterResult=(data,scope)=>{let result=codexLbWorkspaceBaseFilter(data,scope);if(result===data||!result.customSectionsState)return result;let cached=codexLbWorkspaceSections.get(result);if(cached)return cached;let allowed=key=>result.conversationByKey.has(key)||result.entries.some(item=>item.kind==="project"&&item.key===key),sections=result.customSectionsState.sections.map(section=>({...section,itemKeys:section.itemKeys.filter(allowed)})).filter(section=>section.itemKeys.length);cached={...result,customSectionsState:{...result.customSectionsState,sections},customSectionItemKeys:new Set(sections.flatMap(section=>section.itemKeys))};codexLbWorkspaceSections.set(result,cached);return cached};`;
  code = code.replace('{', () => '{' + helper + custom);
  output.set(sidebar.file, sources.get(sidebar.file).replace(sidebar.code, () => code));
  const found = unique([...metadata.code.matchAll(new RegExp(`localProjects:(${ID}),resolvedProjectsWithThreads:\\[\\.\\.\\.(${ID}),\\.\\.\\.(${ID})\\.projectGroups\\]`, 'g'))], 'workspace metadata local projects');
  assert.equal(metadata.code.split('orderedPinnedProjectGroups:').length, 2, 'Unsupported app layout: workspace metadata result');
  const before = 'orderedPinnedProjectGroups:', after = `codexLbLocalProjects:${found[1]},codexLbAllProjectGroups:[...${found[2]},...${found[3]}.projectGroups],` + before;
  const original = output.get(metadata.file) ?? sources.get(metadata.file);
  output.set(metadata.file, original.replace(metadata.code, () => metadata.code.replace(before, () => after)));
  changes.push({ name: 'workspace repository metadata', before, after });
  return { output, changes };
}
function transformWebpackPermissions(sources) {
  const output = new Map(), changes = [];
  const ID = '[A-Za-z_$][\\w$]*';
  const esc = value => value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  let copies = 0;
  for (const [asset, source] of sources) {
    if (!source.includes('sourcePermissionSelection:')) continue;
    const modules = require('node:vm').runInNewContext(source.replaceAll('export const ', 'const ') + '\n;__webpack_modules__', Object.create(null), { timeout: 1000 });
    if (!modules.eYlV) continue;
    const originalModule = modules.eYlV.toString();
    const calls = [...originalModule.matchAll(new RegExp(`sourcePermissionSelection:(${ID})\\(`, 'g'))];
    assert.equal(calls.length, 2, 'Unsupported webpack delegated permission call sites');
    assert.equal(calls[0][1], calls[1][1], 'Unsupported webpack delegated permission resolver');
    const name = calls[0][1];
    const at = originalModule.indexOf('function ' + name + '(');
    const end = originalModule.indexOf('function ', at + 9);
    assert(at >= 0 && end > at, 'Unsupported webpack delegated permission helper');
    const original = originalModule.slice(at, end).trimEnd();
    const pattern = new RegExp(`^function ${esc(name)}\\((${ID}),(${ID}),(${ID}),(${ID}),(${ID})\\)\\{if\\(null==\\2\\)return null;let (${ID})=\\(0,(${ID})\\.JXB\\)\\(\\2\\);if\\(null!=\\4\\)\\{if\\(\\4!==\\3\\)return null\\}else if\\(\\1\\.get\\((${ID})\\.Qk,\\6\\)!==\\3\\)return null;let (${ID})=\\1\\.get\\(\\8\\.we,\\6\\),(${ID})=\\1\\.get\\(\\8\\.JN,\\6\\),(${ID})=null!=\\5&&\\10===\\5&&\\1\\.get\\((${ID})\\.a,\\3\\)\\?\\(0,(${ID})\\.o\\)\\(\\9,\\1\\.get\\(\\8\\.h2,\\6\\)\\):\\9;if\\(null==\\11\\)return null;let (${ID})=\\(0,\\7\\.weu\\)\\(\\11\\);return null==\\14\\?null:\\{agentMode:\\14,permissions:\\11,permissionProfileId:\\11\\.activePermissionProfile\\?\\.id\\?\\?null,sourceCwd:\\10\\}\\}$`);
    const m = original.match(pattern);
    assert(m, 'Unsupported webpack delegated permission helper changed');
    const client = [...new Set([...originalModule.matchAll(new RegExp(`await \\(0,(${ID})\\.V\\)\\(${ID},${ID}\\)\\.sendRequest\\("config/read"`, 'g'))].map(match => match[1]))];
    assert.equal(client.length, 1, 'Unsupported webpack owning app-server client');
    const [, scope, thread, host, sourceHost, cwd, key, threadApi, atoms, permissions, sourceCwd] = m;
    const oldHead = original.slice(0, original.indexOf(`let ${permissions}=`));
    const replacement = `async function ${name}(${scope},${thread},${host},${sourceHost},${cwd}){if(null==${thread})return null;let ${key}=(0,${threadApi}.JXB)(${thread});let codexLbSource=await codexLbReadSourcePermissions({sourceHostId:${sourceHost}??${scope}.get(${atoms}.Qk,${key}),destinationHostId:${host},sourceThreadId:${key},client:(0,${client[0]}.V)(${scope},${host}),toAgentMode:${threadApi}.weu});if(codexLbSource==null)return null;` + original.slice(oldHead.length).replace(`${permissions}=${scope}.get(${atoms}.we,${key}),${sourceCwd}=${scope}.get(${atoms}.JN,${key})`, `${permissions}=codexLbSource.permissions,${sourceCwd}=codexLbSource.sourceCwd`);
    let changedModule = originalModule.replace(original, () => replacement);
    changedModule = changedModule.replace(new RegExp(`sourcePermissionSelection:${esc(name)}\\(`, 'g'), `sourcePermissionSelection:await ${name}(`);
    const brace = changedModule.indexOf('{');
    changedModule = changedModule.slice(0, brace + 1) + `const codexLbReadSourcePermissions=(${readSourcePermissionSelection.toString()});` + changedModule.slice(brace + 1);
    assert.equal(source.split(originalModule).length, 2, 'Ambiguous webpack delegated permissions module');
    output.set(asset, source.replace(originalModule, () => changedModule));
    copies++;
  }
  assert(copies > 0, 'Missing webpack delegated permissions module');
  changes.push({ name: 'delegated source permissions from owning app server', copies });
  return { output, changes };
}
function transformThreadPermissions(source) {
  const ID = '[A-Za-z_$][\\w$]*';
  const callPattern = new RegExp(`sourcePermissionSelection:((?:${ID}\\.type===\x60codexCloud\x60\\?null:)?)(${ID})\\(`, 'g');
  const calls = [...source.matchAll(callPattern)];
  assert.equal(calls.length, 2, 'Unsupported app layout: delegated permission call sites');
  assert.equal(calls[0][2], calls[1][2], 'Unsupported app layout: delegated permission resolver');
  const name = calls[0][2];
  const start = source.indexOf(`function ${name}(`);
  const end = source.indexOf('function ', start + 9);
  assert(start >= 0 && end > start, 'Unsupported app layout: source permission helper');
  const original = source.slice(start, end);
  const args = original.match(new RegExp(`^function ${name.replace(/[$]/g, '\\$&')}\\((${ID}),(${ID}),(${ID}),(${ID})\\)`));
  assert(args, 'Unsupported app layout: source permission arguments');
  const [, scope, thread, host, sourceHost] = args;
  const key = original.match(new RegExp(`let (${ID})=(${ID})\\(${thread}\\)`));
  const permission = original.match(new RegExp(`let (${ID})=${scope}\\.get\\((${ID}),${key?.[1]}\\)`));
  const mode = original.match(new RegExp(`let (${ID})=(${ID})\\(${permission?.[1]}\\)`));
  const hostAtom = original.match(new RegExp(`else if\\(${scope}\\.get\\((${ID}),${key?.[1]}\\)!==${host}\\)return null`));
  const cwdAtom = original.match(new RegExp(`sourceCwd:${scope}\\.get\\((${ID}),${key?.[1]}\\)`));
  const clients = [...new Set([...source.matchAll(new RegExp(`await (${ID})\\((${ID}),(${ID})\\)\\.sendRequest\\(\x60config/read\x60`, 'g'))].map(match => match[1]))];
  assert(key && permission && mode && hostAtom && cwdAtom, 'Unsupported app layout: source permission ownership');
  assert.equal(clients.length, 1, 'Unsupported app layout: owning app-server client');
  const expected = `function ${name}(${scope},${thread},${host},${sourceHost}){if(${thread}==null)return null;let ${key[1]}=${key[2]}(${thread});if(${sourceHost}!=null){if(${sourceHost}!==${host})return null}else if(${scope}.get(${hostAtom[1]},${key[1]})!==${host})return null;let ${permission[1]}=${scope}.get(${permission[2]},${key[1]});if(${permission[1]}==null)return null;let ${mode[1]}=${mode[2]}(${permission[1]});return ${mode[1]}==null?null:{agentMode:${mode[1]},permissions:${permission[1]},permissionProfileId:${permission[1]}.activePermissionProfile?.id??null,sourceCwd:${scope}.get(${cwdAtom[1]},${key[1]})}}`;
  assert.equal(original.trim(), expected, 'Unsupported app layout: source permission helper changed');
  const replacement = `async function ${name}(${scope},${thread},${host},${sourceHost}){if(${thread}==null)return null;let ${key[1]}=${key[2]}(${thread});return codexLbReadSourcePermissions({sourceHostId:${sourceHost}??${scope}.get(${hostAtom[1]},${key[1]}),destinationHostId:${host},sourceThreadId:${key[1]},client:${clients[0]}(${scope},${host}),toAgentMode:${mode[2]}})}`;
  let code = source.slice(0, start) + replacement + source.slice(end);
  code = code.replace(callPattern, (_, guard, resolver) => `sourcePermissionSelection:${guard}await ${resolver}(`);
  code = `const codexLbReadSourcePermissions=(${readSourcePermissionSelection.toString()});` + code;
  return { code, changes: [{ name: 'delegated source permissions from owning app server', before: original, after: replacement }] };
}
const digest = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
function hashFile(file) {
  const fd = fs.openSync(file, 'r'), chunk = Buffer.alloc(4194304), hash = crypto.createHash('sha256');
  try { let bytes; while ((bytes = fs.readSync(fd, chunk, 0, chunk.length, null)) > 0) hash.update(chunk.subarray(0, bytes)); }
  finally { fs.closeSync(fd); }
  return hash.digest('hex');
}
function openArchive(file) {
  const fd = fs.openSync(file, 'r'), prefix = Buffer.alloc(16);
  assert.equal(fs.readSync(fd, prefix, 0, 16, 0), 16);
  assert.equal(prefix.readUInt32LE(0), 4, 'Unsupported ASAR format');
  const size = prefix.readUInt32LE(12);
  assert(size > 0 && size < 64 * 1024 * 1024, 'Invalid ASAR header length');
  const raw = Buffer.alloc(size);
  assert.equal(fs.readSync(fd, raw, 0, size, 16), size);
  const header = JSON.parse(raw.toString('utf8')), entries = new Map();
  function collect(files, parent = '') {
    for (const [name, entry] of Object.entries(files)) {
      const key = parent + name;
      if (entry.files) collect(entry.files, key + '/');
      else entries.set(key, entry);
    }
  }
  collect(header.files);
  const start = 8 + prefix.readUInt32LE(4);
  const read = key => {
    const entry = entries.get(key);
    assert(entry && entry.offset !== undefined && !entry.unpacked, `Missing packed asset: ${key}`);
    const bytes = Buffer.alloc(entry.size);
    assert.equal(fs.readSync(fd, bytes, 0, bytes.length, start + Number(entry.offset)), bytes.length);
    return bytes;
  };
  return { fd, header, entries, start, raw, read };
}
function analyze(appDir) {
  const archivePath = path.join(appDir, 'resources', 'app.asar');
  const executable = path.join(appDir, 'ChatGPT.exe');
  const archive = openArchive(archivePath);
  try {
    let output, changes;
    const webpackAssets = [...archive.entries.keys()].filter(key => /^webview\/assets\/async\/[^/]+\.js$/.test(key));
    if (webpackAssets.length) {
      const sources = new Map(webpackAssets.map(key => [key, archive.read(key).toString('utf8')]));
      output = new Map(); changes = [];
      for (const patch of [transformWebpackUsage, transformWebpackWorkspaces, transformWebpackPermissions]) {
        const result = patch(sources);
        for (const [asset, code] of result.output) { sources.set(asset, code); output.set(asset, code); }
        changes.push(...result.changes);
      }
    } else {
      const assets = [...archive.entries.keys()].filter(key => /^webview\/assets\/app-primary-[^/]+\.js$/.test(key));
      assert.equal(assets.length, 1, 'Expected one primary UI bundle; app layout changed');
      const cache = new Map();
      const readFile = key => {
        if (!cache.has(key)) cache.set(key, archive.read(key).toString('utf8'));
        return cache.get(key);
      };
      const splitAssets = [...archive.entries.keys()].filter(key => /^webview\/assets\/(?:app-primary|app-initial|composer-content|codex-composer-adapter)-[^/]+\.js$/.test(key));
      if (splitAssets.some(key => key.includes('/composer-content-'))) {
        ({ output, changes } = transformSplit(new Map(splitAssets.map(key => [key, readFile(key)])), readFile));
      } else {
        const transformed = transform(readFile(assets[0]), assets[0], readFile);
        output = new Map([[assets[0], transformed.code]]);
        changes = transformed.changes;
      }
      const workspace = transformWorkspaces(output.get(assets[0]) ?? readFile(assets[0]));
      output.set(assets[0], workspace.code);
      changes.push(...workspace.changes);
      const initialAssets = [...archive.entries.keys()].filter(key => /^webview\/assets\/app-initial-[^/]+\.js$/.test(key));
      assert.equal(initialAssets.length, 1, 'Unsupported app layout: workspace metadata bundle');
      const metadata = transformWorkspaceMetadata(output.get(initialAssets[0]) ?? readFile(initialAssets[0]));
      const permissions = transformThreadPermissions(metadata.code);
      output.set(initialAssets[0], permissions.code);
      changes.push(...metadata.changes);
      changes.push(...permissions.changes);
    }
    const modifications = new Map();
    for (const [asset, code] of output) {
      const original = archive.read(asset);
      assert.equal(digest(original), archive.entries.get(asset).integrity?.hash, 'Installed UI integrity mismatch: ' + asset);
      const syntax = spawnSync(process.execPath, ['--check', '--input-type=module'], { input: code, encoding: 'utf8', maxBuffer: 1024 * 1024 });
      assert.equal(syntax.status, 0, 'Patched JavaScript syntax check failed: ' + syntax.stderr);
      modifications.set(asset, { bytes: Buffer.from(code), sourceSha256: digest(original) });
    }
    const originalHeaderHash = digest(archive.raw), binary = fs.readFileSync(executable);
    const at = binary.indexOf(Buffer.from(originalHeaderHash));
    assert(at >= 0 && binary.indexOf(Buffer.from(originalHeaderHash), at + 64) < 0, 'Cannot uniquely resolve embedded ASAR integrity hash');
    return { archive, archivePath, executable, binary, hashOffset: at, originalHeaderHash, modifications, changes };
  } catch (error) {
    fs.closeSync(archive.fd);
    throw error;
  }
}
function verifyArchives(original, output, modifications) {
  const changed = openArchive(output), a = Buffer.alloc(4194304), b = Buffer.alloc(a.length);
  let count = 0;
  try {
    assert.equal(changed.entries.size, original.entries.size);
    for (const [key, entry] of original.entries) {
      const other = changed.entries.get(key);
      assert(other, key);
      if (entry.offset === undefined || entry.unpacked) { assert.deepEqual(other, entry); continue; }
      if (modifications.has(key)) {
        const bytes = changed.read(key);
        assert(bytes.equals(modifications.get(key).bytes));
        assert.equal(digest(bytes), other.integrity.hash);
        for (let offset = 0, index = 0; offset < bytes.length; offset += other.integrity.blockSize, index++) {
          assert.equal(digest(bytes.subarray(offset, offset + other.integrity.blockSize)), other.integrity.blocks[index]);
        }
      } else {
        const { offset: ignoreA, ...metaA } = entry, { offset: ignoreB, ...metaB } = other;
        assert.deepEqual(metaA, metaB, key);
        for (let offset = 0; offset < entry.size;) {
          const size = Math.min(a.length, entry.size - offset);
          assert.equal(fs.readSync(original.fd, a, 0, size, original.start + Number(entry.offset) + offset), size);
          assert.equal(fs.readSync(changed.fd, b, 0, size, changed.start + Number(other.offset) + offset), size);
          assert(a.subarray(0, size).equals(b.subarray(0, size)), 'Unexpected byte change: ' + key);
          offset += size;
        }
      }
      count++;
    }
  } finally { fs.closeSync(changed.fd); }
  return count;
}
function build(appDir, outputDir) {
  const originalPath = path.resolve(appDir), destinationPath = path.resolve(outputDir);
  assert(destinationPath !== originalPath && !destinationPath.startsWith(originalPath + path.sep), 'Refusing to modify the installed application directory');
  const plan = analyze(appDir), { archive } = plan;
  try {
    fs.mkdirSync(path.join(outputDir, 'resources'), { recursive: true });
    const header = JSON.parse(JSON.stringify(archive.header)), packed = [];
    function collect(files, parent = '') {
      for (const [name, entry] of Object.entries(files)) {
        const key = parent + name;
        if (entry.files) collect(entry.files, key + '/');
        else if (entry.offset !== undefined && !entry.unpacked) packed.push({ key, entry, original: archive.entries.get(key) });
      }
    }
    collect(header.files);
    packed.sort((a, b) => Number(a.original.offset) - Number(b.original.offset));
    for (const [asset, { bytes }] of plan.modifications) {
      const target = packed.find(item => item.key === asset);
      target.entry.size = bytes.length;
      const blockSize = target.entry.integrity.blockSize;
      assert(blockSize > 0 && Number.isSafeInteger(blockSize));
      target.entry.integrity = { algorithm: 'SHA256', hash: digest(bytes), blockSize, blocks: [] };
      for (let offset = 0; offset < bytes.length; offset += blockSize) target.entry.integrity.blocks.push(digest(bytes.subarray(offset, offset + blockSize)));
    }
    let offset = 0;
    for (const item of packed) { item.entry.offset = String(offset); offset += item.entry.size; }
    const rawHeader = Buffer.from(JSON.stringify(header)), padding = (4 - rawHeader.length % 4) % 4;
    const headerPickle = Buffer.alloc(8 + rawHeader.length + padding), sizePickle = Buffer.alloc(8);
    headerPickle.writeUInt32LE(headerPickle.length - 4, 0);
    headerPickle.writeUInt32LE(rawHeader.length, 4);
    rawHeader.copy(headerPickle, 8);
    sizePickle.writeUInt32LE(4, 0); sizePickle.writeUInt32LE(headerPickle.length, 4);
    const archiveOutput = path.join(outputDir, 'resources', 'app.asar'), temporary = archiveOutput + '.partial';
    const out = fs.openSync(temporary, 'w'), chunk = Buffer.alloc(4194304);
    try {
      fs.writeSync(out, sizePickle); fs.writeSync(out, headerPickle);
      for (const item of packed) {
        if (plan.modifications.has(item.key)) { fs.writeSync(out, plan.modifications.get(item.key).bytes); continue; }
        for (let offset = 0; offset < item.original.size;) {
          const size = Math.min(chunk.length, item.original.size - offset);
          assert.equal(fs.readSync(archive.fd, chunk, 0, size, archive.start + Number(item.original.offset) + offset), size);
          fs.writeSync(out, chunk, 0, size); offset += size;
        }
      }
    } finally { fs.closeSync(out); }
    const verifiedPackedFiles = verifyArchives(archive, temporary, plan.modifications);
    const newHeaderHash = digest(rawHeader), binary = Buffer.from(plan.binary);
    Buffer.from(newHeaderHash).copy(binary, plan.hashOffset);
    assert(binary.subarray(0, plan.hashOffset).equals(plan.binary.subarray(0, plan.hashOffset)));
    assert(binary.subarray(plan.hashOffset + 64).equals(plan.binary.subarray(plan.hashOffset + 64)));
    const executableOutput = path.join(outputDir, 'ChatGPT.exe');
    fs.writeFileSync(executableOutput + '.partial', binary);
    fs.renameSync(temporary, archiveOutput);
    fs.renameSync(executableOutput + '.partial', executableOutput);
    const manifest = {
      patchFormat: 2, provider: 'codex-lb', builtAt: new Date().toISOString(), sourceApp: appDir,
      assets: [...plan.modifications].map(([asset, { bytes, sourceSha256 }]) => ({ asset, sourceSha256, patchedSha256: digest(bytes) })),
      changes: plan.changes.map(change => change.name),
      sourceHeaderSha256: plan.originalHeaderHash, patchedHeaderSha256: newHeaderHash,
      sourceExecutableSha256: digest(plan.binary), patchedExecutableSha256: digest(binary),
      patchedArchiveSha256: hashFile(archiveOutput),
      sourceArchiveSize: fs.statSync(plan.archivePath).size, verifiedPackedFiles,
      installedFilesModified: false, diagnosticsIncluded: false, executableSignature: 'modified copy is unsigned',
    };
    fs.writeFileSync(path.join(outputDir, 'patch-manifest.json'), JSON.stringify(manifest, null, 2));
    return manifest;
  } finally { fs.closeSync(archive.fd); }
}
function cached(appDir, outputDir) {
  const manifest = JSON.parse(fs.readFileSync(path.join(outputDir, 'patch-manifest.json'), 'utf8'));
  assert.equal(manifest.patchFormat, 2, 'Cached patch format changed; rebuild required');
  const source = openArchive(path.join(appDir, 'resources', 'app.asar'));
  const output = openArchive(path.join(outputDir, 'resources', 'app.asar'));
  try {
    assert.equal(digest(source.raw), manifest.sourceHeaderSha256);
    assert.equal(digest(output.raw), manifest.patchedHeaderSha256);
    assert.equal(digest(fs.readFileSync(path.join(appDir, 'ChatGPT.exe'))), manifest.sourceExecutableSha256);
    assert.equal(digest(fs.readFileSync(path.join(outputDir, 'ChatGPT.exe'))), manifest.patchedExecutableSha256);
    for (const { asset, sourceSha256, patchedSha256 } of manifest.assets) {
      assert.equal(digest(source.read(asset)), sourceSha256);
      assert.equal(digest(output.read(asset)), patchedSha256);
    }
    assert.equal(hashFile(path.join(outputDir, 'resources', 'app.asar')), manifest.patchedArchiveSha256);
    assert.equal(fs.statSync(path.join(appDir, 'resources', 'app.asar')).size, manifest.sourceArchiveSize);
    return true;
  } finally { fs.closeSync(source.fd); fs.closeSync(output.fd); }
}
if (true) {
  try {
    const [action, source, output] = process.argv.slice(2);
    if (!source || !['check', 'build', 'cached'].includes(action)) throw new Error('Usage: node patch-asar.cjs check|build|cached SOURCE_APP [OUTPUT_APP]');
    if (action === 'check') {
      const plan = analyze(source);
      try { console.log(JSON.stringify({ compatible: true, assets: [...plan.modifications.keys()], changes: plan.changes.map(change => change.name), sourceHeaderSha256: plan.originalHeaderHash })); }
      finally { fs.closeSync(plan.archive.fd); }
    } else if (action === 'cached') { cached(source, output); console.log('Cached patch verified.'); }
    else console.log(JSON.stringify(build(source, output), null, 2));
  } catch (error) { console.error(error.message); process.exitCode = 1; }
}
module.exports = { transformWebpackUsage, transformWebpackWorkspaces, transformWebpackPermissions, analyze, build, cached, openArchive, createWorkspaceFilter, transformWorkspaces, readSourcePermissionSelection, transformThreadPermissions };
'@
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
function Set-CodexLauncherShortcut {
    param($Package, [string]$Release, [string]$AppExe)
    # The Store package's logo differs from the embedded executable icon.
    $variant = 'unplated'
    $theme = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -ErrorAction SilentlyContinue
    if ($theme -and $theme.SystemUsesLightTheme -eq 1) { $variant = 'lightunplated' }
    $assets = Join-Path $Package.InstallLocation 'assets'
    $frames = @(foreach ($size in @(16, 20, 24, 32, 48, 64, 96, 256)) {
        $png = Join-Path $assets ('Square44x44Logo.targetsize-' + $size + '_altform-' + $variant + '.png')
        if (Test-Path -LiteralPath $png) {
            [pscustomobject]@{ Size = $size; Bytes = [System.IO.File]::ReadAllBytes($png) }
        }
    })
    $icon = $AppExe
    if ($frames.Count) {
        $icon = Join-Path $Release ('codex-' + $variant + '.ico')
        $stream = [System.IO.MemoryStream]::new()
        $writer = [System.IO.BinaryWriter]::new($stream)
        try {
            $writer.Write([uint16]0)
            $writer.Write([uint16]1)
            $writer.Write([uint16]$frames.Count)
            $offset = 6 + 16 * $frames.Count
            foreach ($frame in $frames) {
                $dimension = if ($frame.Size -eq 256) { 0 } else { $frame.Size }
                $writer.Write([byte]$dimension)
                $writer.Write([byte]$dimension)
                $writer.Write([byte]0)
                $writer.Write([byte]0)
                $writer.Write([uint16]1)
                $writer.Write([uint16]32)
                $writer.Write([uint32]$frame.Bytes.Length)
                $writer.Write([uint32]$offset)
                $offset += $frame.Bytes.Length
            }
            foreach ($frame in $frames) { $writer.Write([byte[]]$frame.Bytes) }
            $writer.Flush()
            $bytes = $stream.ToArray()
            if (!(Test-Path -LiteralPath $icon) -or [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($icon)) -ne [Convert]::ToBase64String($bytes)) {
                [System.IO.File]::WriteAllBytes($icon, $bytes)
            }
        } finally { $writer.Dispose(); $stream.Dispose() }
    }
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Desktop')) 'Codex (codex-lb).lnk'))
    $shortcut.TargetPath = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $shortcut.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '" -ShowErrors -OutputRoot "' + $OutputRoot.TrimEnd('\') + '" -CodexHome "' + $CodexHome.TrimEnd('\') + '"'
    $shortcut.WorkingDirectory = $PSScriptRoot
    $shortcut.WindowStyle = 7
    $shortcut.Description = 'Patch the current Codex installation and open your normal profile.'
    $shortcut.IconLocation = $icon + ',0'
    $shortcut.Save()
}
$launcherMutex = [System.Threading.Mutex]::new($false, 'Local\CodexLbLauncher')
$launcherLockHeld = $false
try {
    try { $launcherLockHeld = $launcherMutex.WaitOne(0) }
    catch [System.Threading.AbandonedMutexException] { $launcherLockHeld = $true }
    if (!$launcherLockHeld) { Write-Host 'Another Codex-lb launcher is already running.'; exit 0 }
    $node = (Get-Command node.exe -ErrorAction Stop).Source
    $package = Get-AppxPackage -Name OpenAI.Codex | Sort-Object { [version]$_.Version } -Descending | Select-Object -First 1
    if (!$package) { throw 'The Codex Store installation was not found.' }
    $sourceApp = Join-Path $package.InstallLocation 'app'
    Write-Host ('Installed Codex: ' + $package.Version)
    if ($CheckOnly) {
        $engineCode | & $node - check $sourceApp
        if ($LASTEXITCODE -ne 0) { throw 'This app version needs an updated patch rule.' }
        exit 0
    }
    $engineHash = [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes($engineCode))).Replace('-', '').ToLowerInvariant()
    $ruleHash = $engineHash.Substring(0, 12)
    $release = Join-Path $OutputRoot ($package.Version.ToString() + '-' + $ruleHash)
    $runtime = Join-Path $release 'app'
    $appExe = Join-Path $runtime 'ChatGPT.exe'
    $ready = $false
    if (Test-Path -LiteralPath (Join-Path $runtime 'patch-manifest.json')) {
        $engineCode | & $node - cached $sourceApp $runtime
        $ready = $LASTEXITCODE -eq 0
    }
    if (!$ready) {
        # Check all structural anchors before copying or changing the staged build.
        $engineCode | & $node - check $sourceApp
        if ($LASTEXITCODE -ne 0) { throw 'This app version needs an updated patch rule; the installed app was left untouched.' }
        $inUse = @(Get-CimInstance Win32_Process -Filter "Name = 'ChatGPT.exe'" | Where-Object { $_.ExecutablePath -eq $appExe })
        if ($inUse.Count) { throw 'The staged build needs repair but is running. Quit it and run this launcher again.' }
        New-Item -ItemType Directory -Path $runtime -Force | Out-Null
        Write-Host 'Preparing a patched copy of the current installation...'
        & robocopy.exe $sourceApp $runtime /E /COPY:DAT /DCOPY:DAT /R:1 /W:1 /NFL /NDL /NJH /NJS /NP
        if ($LASTEXITCODE -ge 8) { throw 'Copying the installed app failed.' }
        $engineCode | & $node - build $sourceApp $runtime
        if ($LASTEXITCODE -ne 0) { throw 'Patch verification failed. The staged app will not launch.' }
        $engineCode | & $node - cached $sourceApp $runtime
        if ($LASTEXITCODE -ne 0) { throw 'Final verification failed.' }
    }
    Set-Content -LiteralPath (Join-Path $OutputRoot 'latest-release.txt') -Value $runtime
    try { Set-CodexLauncherShortcut -Package $package -Release $release -AppExe $appExe }
    catch { Write-Warning ('Could not update the desktop shortcut: ' + $_.Exception.Message) }
    if ($PrepareOnly) { Write-Host ('Ready: ' + $appExe); exit 0 }

    $profile = Join-Path $env:LOCALAPPDATA ('Packages\' + $package.PackageFamilyName + '\LocalCache\Roaming\Codex\web\Codex')
    if (!(Test-Path -LiteralPath $profile)) { $profile = Join-Path $env:APPDATA 'Codex\web\Codex' }
    if (!(Test-Path -LiteralPath $profile)) { throw 'The normal Codex profile was not found.' }
    $running = @(Get-CimInstance Win32_Process -Filter "Name = 'ChatGPT.exe'" | Where-Object { $_.CommandLine -notmatch '--type=' })
    if ($running.Count -and $NoRestart) { throw 'Codex is running. Quit it first, or run without -NoRestart to switch instances.' }
    if ($running.Count) {
        Write-Host 'Restarting Codex to load the patched build...'
        foreach ($app in $running) {
            $process = Get-Process -Id $app.ProcessId -ErrorAction SilentlyContinue
            if ($process -and $process.MainWindowHandle -ne 0) { $null = $process.CloseMainWindow() }
        }
        Start-Sleep -Seconds 2
        # Closing a Codex window may leave its background process alive.
        $ownedPaths = @($running | ForEach-Object { $_.ExecutablePath })
        Get-CimInstance Win32_Process -Filter "Name = 'ChatGPT.exe'" | Where-Object { $_.ExecutablePath -in $ownedPaths } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
        Start-Sleep -Seconds 2
    }
    $remaining = @(Get-CimInstance Win32_Process -Filter "Name = 'ChatGPT.exe'" | Where-Object { $_.CommandLine -notmatch '--type=crashpad-handler' })
    if ($remaining.Count) { throw 'A Codex instance is still running; refusing to share its profile.' }
    $backup = Join-Path $release ('profile-state-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    New-Item -ItemType Directory -Path $backup -Force | Out-Null
    foreach ($name in @('.codex-global-state.json', 'config.toml')) {
        $file = Join-Path $CodexHome $name
        if (Test-Path -LiteralPath $file) { Copy-Item -LiteralPath $file -Destination $backup }
    }
    $env:CODEX_HOME = $CodexHome
    $process = Start-Process -FilePath $appExe -WorkingDirectory $runtime -ArgumentList ('--user-data-dir="' + $profile + '"') -PassThru
    Write-Host ('Opened patched Codex, PID ' + $process.Id + ', with your normal profile.')
    exit 0
} catch {
    $launcherErrorMessage = $_.Exception.Message
    if ($ShowErrors) { try { $null = (New-Object -ComObject WScript.Shell).Popup($launcherErrorMessage, 0, 'Codex patch failed', 16) } catch {} }
    Write-Error $launcherErrorMessage -ErrorAction Continue
    exit 1
} finally {
    if ($launcherLockHeld) { $launcherMutex.ReleaseMutex() }
    $launcherMutex.Dispose()
}
