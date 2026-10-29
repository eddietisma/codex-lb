'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const Module = require('node:module');
const { test } = require('node:test');

const scriptPath = path.join(__dirname, '..', 'Patch-Codex.ps1');
const engine = fs.readFileSync(scriptPath, 'utf8').match(/\$engineCode = @'\r?\n([\s\S]*?)\r?\n'@/)[1];
const loaded = new Module(scriptPath, module);
loaded._compile(engine.replace('if (true) {', 'if (false) {'), scriptPath);
const { createWorkspaceFilter, transformWorkspaces } = loaded.exports;
const projectKey = id => `codex:project:${id}`;
const chatProjectKey = id => `chatgpt:project:${id}`;
const threadKey = id => `codex:thread:${id}`;
const atom = Symbol('thread');
const hsbFolders = ['F:/HSB', 'E:/work/PLAT-387', 'E:/work/PLAT-370'];
const roarFolders = ['/srv/RoarDB'];

function fixture(active = '', chatMetadata) {
  const hsb = { projectId: 'hsb', path: 'F:\\HSB\\search', threadKeys: ['hsb'] };
  const roar = { projectId: 'roar', path: '/srv/RoarDB', threadKeys: ['roar', 'worktree'] };
  const plat = { projectId: 'plat', rootPaths: ['E:/work/PLAT-387'], threadKeys: ['plat'] };
  const records = {
    hsb: { kind: 'local', summary: { cwd: 'F:\\HSB\\search' } },
    roar: { kind: 'local', summary: { cwd: '/srv/RoarDB' } },
    worktree: { kind: 'local', summary: { cwd: 'E:/.worktrees/random-id' } },
    plat: { kind: 'local', summary: { cwd: 'E:/work/PLAT-387' } },
    folder: { kind: 'local', summary: { cwd: 'E:/work/PLAT-370/tools' } },
    sibling: { kind: 'local', summary: { cwd: 'F:/HSB-other' } },
    unrelated: { kind: 'local', summary: { cwd: 'F:/other', title: 'HSB and PLAT-387',
      gitInfo: { originUrl: 'https://example.com/HSB/search' } } },
  };
  const scope = { get(selectedAtom, id) { assert.equal(selectedAtom, atom); return records[id]; } };
  const projects = [hsb, roar, plat];
  const conversationByKey = new Map(Object.keys(records).map(id => [threadKey(id), { source: 'codex', threadKey: id }]));
  conversationByKey.set('chatgpt:conversation:linked', { source: 'chatgpt', target: { projectId: 'mirror' } });
  conversationByKey.set('chatgpt:conversation:other', { source: 'chatgpt', target: { conversation: { title: 'HSB' } } });
  const chatGptProjectTargets = [{ project: { gizmo: { id: 'mirror', display: { name: 'Search tools' } } }, localThreadKeys: ['hsb'] }];
  const keys = [...projects.map(group => projectKey(group.projectId)), chatProjectKey('mirror'), ...conversationByKey.keys()];
  const data = { orderedPinnedProjectGroups: [roar], allCodexProjectGroups: projects,
    codexProjectGroups: projects, chatGptProjectTargets,
    linkedLocalProjectIdByChatGptProjectId: new Map([['mirror', 'hsb']]), conversationByKey,
    entries: keys.map(key => ({ key })),
    layout: { pinnedKeys: [threadKey('worktree'), threadKey('hsb')],
      projectKeys: keys.filter(key => key.includes(':project:')), chatKeys: [...conversationByKey.keys()],
      chatAttentionStates: [...conversationByKey.keys()].map(key => key === threadKey('roar') ? 'unread' : 'idle') } };
  const effects = [];
  const state = { workspaces: [{ name: 'HSB', folders: hsbFolders }, { name: 'RoarDB', folders: roarFolders },
    { name: 'Empty', folders: [] }], active };
  const previous = global.localStorage;
  global.localStorage = { getItem: () => JSON.stringify(state), setItem() {} };
  let filter;
  try {
    filter = createWorkspaceFilter(() => ({ useSyncExternalStore: (_, snapshot) => snapshot(),
      useMemo: fn => fn(), useEffect: fn => effects.push(fn) }),
      () => ({}), () => atom, projectKey, chatProjectKey, chatMetadata);
  } finally {
    if (previous === undefined) delete global.localStorage;
    else global.localStorage = previous;
  }
  return { data, scope, filter, effects, records };
}

test('All preserves selector results while an empty workspace matches nothing', () => {
  const { data, scope, filter } = fixture();
  assert.equal(filter.filter(data, scope, null), data);
  const empty = filter.filter(data, scope, []);
  assert.deepEqual(empty.layout.projectKeys, []);
  assert.deepEqual(empty.layout.chatKeys, []);
  assert.equal(empty.conversationByKey.size, 0);
  assert.equal(filter.filter(data, scope, null), data);
});

test('one workspace includes several explicit folders and their linked projects', () => {
  const { data, scope, filter } = fixture();
  const result = filter.filter(data, scope, hsbFolders);
  assert.deepEqual(result.layout.projectKeys, [projectKey('hsb'), projectKey('plat'), chatProjectKey('mirror')]);
  assert.deepEqual(result.layout.chatKeys, [threadKey('hsb'), threadKey('plat'), threadKey('folder'), 'chatgpt:conversation:linked']);
  assert.deepEqual(result.layout.pinnedKeys, [threadKey('hsb')]);
  assert(!result.conversationByKey.has(threadKey('sibling')));
  assert(!result.conversationByKey.has(threadKey('unrelated')));
  assert(!result.conversationByKey.has('chatgpt:conversation:other'));
  assert(!result.entries.some(item => item.key === threadKey('roar')));
  assert.equal(data.layout.pinnedKeys.length, 2);
});

test('Windows paths normalize slash and case, require a path boundary, and accept drive roots', () => {
  const { filter } = fixture();
  assert(filter.matches({ cwd: 'f:\\hsb\\search\\src' }, ['F:/HSB/']));
  assert(filter.matches({ cwd: 'F:/HSB' }, ['f:\\hsb']));
  assert(!filter.matches({ cwd: 'F:/HSB-other' }, ['F:/HSB']));
  assert(!filter.matches({ cwd: 'F:/other/HSB' }, ['F:/HSB']));
  assert(filter.matches({ cwd: 'F:/anything/nested' }, ['F:/']));
  assert(!filter.matches({ cwd: 'E:/anything' }, ['F:/']));
});

test('Unix folders include children, exclude siblings, and preserve case', () => {
  const { filter } = fixture();
  assert(filter.matches({ cwd: '/srv/RoarDB/src' }, ['/srv/RoarDB/']));
  assert(!filter.matches({ cwd: '/srv/RoarDB-copy' }, ['/srv/RoarDB']));
  assert(!filter.matches({ cwd: '/srv/roardb' }, ['/srv/RoarDB']));
  assert(filter.matches({ cwd: '/srv/RoarDB' }, ['/']));
});

test('matching reads folder metadata rather than labels, repo names, URLs, or prose', () => {
  const { filter } = fixture();
  assert(filter.matches({ rootPaths: ['F:/tools', 'E:/work/PLAT-387'] }, hsbFolders));
  assert(filter.matches({ pendingWorktree: { sourceWorkspaceRoot: 'F:/HSB/search' } }, hsbFolders));
  assert(filter.matches({ pendingThreadStart: { task: { cwd: 'E:/work/PLAT-370' } } }, hsbFolders));
  assert(!filter.matches({ label: 'F:/HSB', title: 'F:/HSB', repoName: 'F:/HSB',
    gitInfo: { originUrl: 'F:/HSB' }, task: { description: 'F:/HSB' } }, hsbFolders));
  assert(filter.matches({ cwd: 'F:/other' }, null));
  assert(!filter.matches({ cwd: 'F:/HSB' }, []));
});

test('original project roots retain worktree chats whose working directories are elsewhere', () => {
  const { data, scope, filter } = fixture();
  const result = filter.filter(data, scope, roarFolders);
  assert.deepEqual(result.layout.chatKeys, [threadKey('roar'), threadKey('worktree')]);
  assert.deepEqual(result.layout.pinnedKeys, [threadKey('worktree')]);
  assert.deepEqual(result.codexProjectGroups.map(group => group.projectId), ['roar']);
});

test('linked generic projects match configured folders when their visible local group is absent', () => {
  const { data, scope, filter } = fixture();
  data.codexLbAllProjectGroups = [];
  data.codexLbLocalProjects = { hsb: { rootPaths: ['F:/HSB/search'] } };
  data.allCodexProjectGroups = data.allCodexProjectGroups.filter(group => group.projectId !== 'hsb');
  const result = filter.filter(data, scope, hsbFolders);
  assert(result.layout.projectKeys.includes(chatProjectKey('mirror')));
  assert(result.layout.chatKeys.includes('chatgpt:conversation:linked'));
});

test('current folder metadata controls a chat after it moves between folders', () => {
  const { data, scope, filter, records } = fixture();
  assert(filter.filter(data, scope, hsbFolders).conversationByKey.has(threadKey('folder')));
  records.folder = { kind: 'local', summary: { cwd: '/srv/RoarDB/tools' } };
  assert(!filter.filter(data, scope, hsbFolders).conversationByKey.has(threadKey('folder')));
  assert(filter.filter(data, scope, roarFolders).conversationByKey.has(threadKey('folder')));
});

test('unread indicators exclude chats outside the selected folders', () => {
  const { data, scope, filter } = fixture();
  const result = filter.filter(data, scope, hsbFolders);
  assert(result.layout.chatAttentionStates.every(state => state === 'idle'));
  assert.equal(result.layout.chatAttentionStates.length, result.layout.chatKeys.length);
});

test('connection groups and keyboard shortcuts use the selected workspace folders', () => {
  const { data, scope, filter } = fixture('HSB');
  const native = { projectGroups: data.allCodexProjectGroups,
    connectionGroups: [{ key: 'server', threadKeys: ['hsb', 'roar', 'folder', 'sibling', 'plat'] }],
    shortcutThreadKeys: ['hsb', 'roar', 'folder', 'sibling', 'plat'], navigationThreadKeys: ['roar', 'hsb'] };
  const result = filter.filterNative(native, scope);
  assert.deepEqual(result.shortcutThreadKeys, ['hsb', 'folder', 'plat']);
  assert.deepEqual(result.navigationThreadKeys, ['hsb']);
  assert.deepEqual(result.connectionGroups[0].threadKeys, ['hsb', 'folder', 'plat']);
});

test('selected workspace with no folders hides native and priority items', () => {
  const { data, scope, filter } = fixture('Empty');
  const native = filter.filterNative({ projectGroups: data.allCodexProjectGroups, threadKeys: ['hsb'] }, scope);
  assert.deepEqual(native.projectGroups, []);
  assert.deepEqual(native.threadKeys, []);
  assert.deepEqual(filter.filterPriority([{ kind: 'task', threadEntry: { key: 'hsb' } }], scope), []);
});

test('filtering sparse history does not fetch additional pages or schedule effects', async () => {
  const { data, scope, filter, effects } = fixture('HSB');
  data.conversationByKey = new Map();
  data.layout.chatKeys = [];
  let calls = 0;
  for (let page = 0; page < 1000; page++) {
    const result = filter.filterResult({ ...data }, scope, { hasMore: true, loading: false, loadMore: async () => { calls++; } });
    assert.equal(result.layout.chatKeys.length, 0);
  }
  await Promise.resolve();
  assert.equal(calls, 0);
  assert.deepEqual(effects, []);
});

test('an unconfigured workspace does not read any thread metadata', () => {
  const { data, filter } = fixture('Empty');
  const scope = { get() { assert.fail('Empty workspace should not materialize thread metadata'); } };
  assert.deepEqual(filter.filterResult(data, scope).layout.chatKeys, []);
  assert.deepEqual(filter.filterNative({ projectGroups: data.allCodexProjectGroups, threadKeys: ['hsb', 'roar'] }, scope).threadKeys, []);
  assert.deepEqual(filter.filterPriority([{ kind: 'task', threadEntry: { key: 'hsb' } }], scope), []);
});

test('native matching uses known project roots before resolving thread metadata', () => {
  const { data, filter } = fixture('HSB');
  const scope = { get() { assert.fail('Matching project already supplies the thread folder'); } };
  const result = filter.filterNative({ projectGroups: [data.allCodexProjectGroups[0]], threadKeys: ['hsb'] }, scope);
  assert.deepEqual(result.threadKeys, ['hsb']);
});

test('priority and grouped recent items use explicit roots, including linked generic projects', () => {
  const { scope, filter } = fixture('HSB', (_, item) => ({
    localProjects: item.conversation?.gizmo_id === 'mirror' ? [{ rootPaths: ['F:/HSB/search'] }] : [],
  }));
  const hsb = { kind: 'task', threadEntry: { key: 'hsb', cwd: 'F:/HSB/search' } };
  const roar = { kind: 'task', threadEntry: { key: 'roar', cwd: '/srv/RoarDB' } };
  const worktree = { kind: 'task', threadEntry: { key: 'worktree' }, projectGroup: { path: 'E:/work/PLAT-387' } };
  const linked = { kind: 'chatgpt', source: 'server', conversation: { gizmo_id: 'mirror', title: 'Search tools' } };
  const other = { kind: 'chatgpt', source: 'server', conversation: { title: 'F:/HSB' } };
  assert.deepEqual(filter.filterPriority([hsb, roar, worktree, linked, other], scope), [hsb, worktree, linked]);
  assert.deepEqual(filter.filterPriority([{ dayStart: 1, items: [hsb, roar] }, { dayStart: 2, items: [roar] }], scope),
    [{ dayStart: 1, items: [hsb] }]);
  assert.equal(filter.filterPriority(null, scope), null);
});

test('unknown app layouts stop before patching', () => {
  assert.throws(() => transformWorkspaces('export {};'), /Unsupported app layout/);
});
