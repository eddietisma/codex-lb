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
  function filterResult(data, scope, paging) {
    const folders = selectedFolders(useWorkspace());
    const result = filter(data, scope, folders);
    react().useEffect(() => {
      if (!folders?.length || result.layout.chatKeys.length >= 10 || paging.loading || !paging.hasMore) return;
      let cancelled = false;
      // Continue through nonmatching history pages, including an initially empty result.
      Promise.resolve().then(() => { if (!cancelled) return paging.loadMore(); }).catch(() => {});
      return () => { cancelled = true; };
    }, [folders, result, paging.loading, paging.hasMore, paging.reader, paging.pageScope]);
    return result;
  }
  function filter(data, scope, folders = selectedFolders()) {
    if (folders === null) return data;
    const selection = JSON.stringify(folders);
    const previous = cache.get(data);
    const groups = data.codexLbAllProjectGroups ?? [...data.orderedPinnedProjectGroups, ...data.allCodexProjectGroups];
    const allowedProjects = new Set(), allowedThreads = new Set();
    for (const group of groups) {
      if (!matches(group, folders)) continue;
      allowedProjects.add(projectKey(group.projectId));
      for (const key of group.threadKeys) allowedThreads.add(key);
    }
    for (const item of data.chatGptProjectTargets) {
      const id = item.project.gizmo.id, linkedId = data.linkedLocalProjectIdByChatGptProjectId.get(id);
      if (allowedProjects.has(projectKey(linkedId)) || matches(data.codexLbLocalProjects?.[linkedId], folders)) {
        allowedProjects.add(chatProjectKey(id));
        for (const key of item.localThreadKeys ?? []) allowedThreads.add(key);
      }
    }
    const conversationByKey = new Map();
    for (const [key, item] of data.conversationByKey) {
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
      style: { flexShrink: 0, border: '1px solid var(--border-color, #6666)', borderRadius: 999,
        padding: '4px 10px', background: active ? 'var(--color-token-bg-secondary, #8883)' : 'transparent',
        color: 'inherit', font: 'inherit', cursor: 'pointer', fontWeight: active ? 600 : 400 }, children: label,
    }, label);
    return h('div', { 'data-codex-lb-workspaces': true, style: { minWidth: 0, padding: '8px 12px' }, children: [
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
    return { ...props, topContent: h(react().Fragment, { children: [h(Controls, {}, 'workspaces'),
      h(react().Fragment, { children: props.topContent }, 'original')] }) };
  }
  function filterNative(data, scope) {
    const folders = selectedFolders(useWorkspace());
    const threadKeys = [...new Set(['threadKeys', 'chatSectionThreadKeys', 'pinnedProjectThreadKeys', 'navigationThreadKeys', 'shortcutThreadKeys']
      .flatMap(key => data[key] ?? []).concat(data.projectGroups.flatMap(group => group.threadKeys),
        data.connectionGroups?.flatMap(group => group.threadKeys) ?? []))];
    const matchingThreads = new Set(folders === null ? [] : threadKeys.filter(key => matches(scope.get(threadAtom(), key), folders)));
    const membership = JSON.stringify([...matchingThreads]);
    return react().useMemo(() => {
      if (folders === null) return data;
      const allowedThreads = new Set();
      const projectGroups = data.projectGroups.filter(group => {
        if (!matches(group, folders)) return false;
        for (const key of group.threadKeys) allowedThreads.add(key);
        return true;
      });
      const allowed = key => allowedThreads.has(key) || matchingThreads.has(key);
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
  const catalog = sidebar.match(new RegExp(`(${ID})!=null&&(${ID})!=null\\?\\1\\.getPageState\\(\\2\\)`));
  const pageState = sidebar.match(new RegExp(`(${ID})=\\(0,${ID}\\.useSyncExternalStore\\)`));
  // Resolve the ChatGPT history hook directly instead of relying on unrelated locals.
  const historyCall = sidebar.match(new RegExp(`let (${ID})=(${ID})\\((${ID})\\),${ID};(?=.*?chatTargets:)`));
  assert(catalog && pageState && historyCall, 'Unsupported app layout: sidebar history paging');
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
  const before = selector[0], after = `${selector[1]}=codexLbWorkspace.filterResult(${selector[2]}(${selector[3]},${selector[4]}),${scope[1]},{reader:${catalog[1]},pageScope:${catalog[2]},hasMore:${pageState[1]}.hasMore||${historyCall[1]}.canFetchNextConversationPage,loading:${pageState[1]}.isLoading||${historyCall[1]}.isFetchingNextConversationPage,loadMore:()=>Promise.all([${pageState[1]}.hasMore?${catalog[1]}?.loadMore(${catalog[2]},50):void 0,${historyCall[1]}.canFetchNextConversationPage?${historyCall[1]}.fetchNextConversationPage(50):void 0])}),{orderedPinnedProjectGroups:`;
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
function transformCatalogDiscovery(source) {
  const method = [...source.matchAll(/async sendEnablement\(([A-Za-z_$][\w$]*),[A-Za-z_$][\w$]*\)\{let [A-Za-z_$][\w$]*=await this\.evaluations\.readExecutionAssignments\(\);/g)];
  const enabled = [...source.matchAll(/([A-Za-z_$][\w$]*)\.codex_apps_mcp_2026_07_28=!0,/g)];
  assert.equal(method.length, 1, 'Unsupported app layout: model discovery enablement');
  assert.equal(enabled.length, 1, 'Unsupported app layout: model discovery feature flags');
  assert(method[0].index < enabled[0].index, 'Unsupported app layout: model discovery ordering');
  const connection = method[0][1] + '.connection';
  const before = enabled[0][0];
  const after = `if(${connection}.hostId===\`local\`){const{config:codexLbCatalogConfig}=await ${connection}.sendAppServerRequest(\`config/read\`,{includeLayers:!1});if(codexLbCatalogConfig.model_provider===\`codex-lb\`&&typeof codexLbCatalogConfig.model_providers?.[\`codex-lb\`]?.model_catalog_url===\`string\`&&codexLbCatalogConfig.model_providers[\`codex-lb\`].model_catalog_url.trim()!==\`\`)${enabled[0][1]}.api_key_model_discovery=!0;}${before}`;
  return { code: source.replace(before, after), changes: [{ name: 'keep explicit CodexLB catalog discovery enabled' }] };
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
    const assets = [...archive.entries.keys()].filter(key => /^webview\/assets\/app-primary-[^/]+\.js$/.test(key));
    assert.equal(assets.length, 1, 'Expected one primary UI bundle; app layout changed');
    const cache = new Map();
    const readFile = key => {
      if (!cache.has(key)) cache.set(key, archive.read(key).toString('utf8'));
      return cache.get(key);
    };
    let output, changes;
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
    output.set(initialAssets[0], metadata.code);
    changes.push(...metadata.changes);
    const mainAssets = [...archive.entries.keys()].filter(key => /^\.vite\/build\/main-[^/]+\.js$/.test(key));
    assert.equal(mainAssets.length, 1, 'Unsupported app layout: main catalog discovery bundle');
    const mainCatalog = transformCatalogDiscovery(readFile(mainAssets[0]));
    output.set(mainAssets[0], mainCatalog.code);
    changes.push(...mainCatalog.changes);
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
module.exports = { analyze, build, cached, openArchive, createWorkspaceFilter, transformWorkspaces, transformCatalogDiscovery };
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
