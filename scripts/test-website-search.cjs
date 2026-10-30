const assert = require('node:assert/strict')
const fs = require('node:fs')
const vm = require('node:vm')
const path = require('node:path')

const source = fs.readFileSync(path.join(__dirname, '../website/assets/site.js'), 'utf8')
const sandbox = {
  document: { currentScript: { src: '/assets/site.js' }, documentElement: { lang: 'en' } },
}
const demoSource = source.slice(0, source.indexOf("  document.querySelectorAll('[data-mock]')"))
vm.runInNewContext(demoSource
  + 'globalThis.search = { searchWindows, highlight, MRU0, APPS, barHTML, sidebarDefaults, settingsForm, switcherWindows, swRows, MOCKS, BODY }; })()', sandbox)
const { searchWindows, highlight, MRU0, APPS } = sandbox.search
const results = query => Array.from(searchWindows(MRU0, query))

assert.match(sandbox.search.MOCKS.search(), /chr context/)
assert.doesNotMatch(sandbox.search.MOCKS.search(), /weix|pinyin/i)
for (const body of Object.values(sandbox.search.BODY)) assert.doesNotMatch(body(), /weix|pinyin/i)
const chinese = { document: { currentScript: { src: '/assets/site.js' }, documentElement: { lang: 'zh-CN' } } }
vm.runInNewContext(demoSource + 'globalThis.mockSearch = MOCKS.search(); })()', chinese)
assert.match(chinese.mockSearch, /weix/)
assert.match(chinese.mockSearch, /<mark>微信<\/mark>/)

assert.deepEqual(results(''), Array.from(MRU0))
assert.deepEqual(results('   '), Array.from(MRU0))
assert.deepEqual(results('CHROME'), ['chrome'])
assert.deepEqual(results('chr context'), ['chrome'])
assert.deepEqual(results('  context   chr  '), ['chrome'])
assert.deepEqual(results('gchr'), [])
assert.deepEqual(results('chr missing'), [])
assert.deepEqual(results('no such window'), [])
assert.equal(results('chatgpt')[0], 'chatgpt')
assert.deepEqual(results('context'), ['terminal', 'chrome', 'slack', 'notes'])
assert.equal(highlight('Google Chrome', 'chr context'), 'Google <mark>Chr</mark>ome')
assert.equal(highlight('Google Chrome', 'ch hro'), 'Google <mark>Chro</mark>me')
assert.equal(highlight('Google Chrome', ''), 'Google Chrome')
assert.equal(highlight('<img>&"', '<img>'), '<mark>&lt;img&gt;</mark>&amp;&quot;')
assert.equal(highlight('Google Chrome', '.*'), 'Google Chrome')
APPS.exact = { name: 'Context', title: 'Example' }
assert.equal(searchWindows([...MRU0, 'exact'], 'context')[0], 'exact')

assert.deepEqual(results('weixin'), ['wechat'])
assert.deepEqual(results('WEIX'), ['wechat'])
assert.deepEqual(results('weixin xiangmu'), ['wechat'])
assert.deepEqual(results('fabu'), ['notes'])
assert.deepEqual(results('qingd'), ['notes'])
for (const query of ['wx', 'eixin', 'xiangm missing']) assert.deepEqual(results(query), [])
assert.equal(highlight('微信', 'weix'), '<mark>微信</mark>')
assert.equal(highlight('微信', 'wei'), '<mark>微</mark>信')
assert.equal(highlight('项目讨论 — 微信', 'xiangmu wei'), '<mark>项目</mark>讨论 — <mark>微</mark>信')
assert.equal(highlight('发布清单', 'fabu qingd'), '<mark>发布清单</mark>')
assert.equal(highlight('😀微信', 'weix'), '😀<mark>微信</mark>')
APPS.literal = { name: 'weixin', title: 'Example' }
assert.equal(searchWindows(['wechat', 'literal'], 'weixin')[0], 'literal')

const { switcherWindows, swRows } = sandbox.search
const windows = (query, allDesktops, desktop, mru = MRU0) => Array.from(switcherWindows(mru, query, allDesktops, desktop))
assert.deepEqual(windows('', false, 1), ['terminal', 'chrome', 'finder', 'notes', 'wechat'])
assert.deepEqual(windows('', true, 1), ['terminal', 'chrome', 'finder', 'notes', 'wechat', 'claude', 'slack', 'chatgpt'])
assert.deepEqual(windows('', true, 2), ['slack', 'claude', 'finder', 'chrome', 'notes', 'terminal', 'wechat', 'chatgpt'])
assert.deepEqual(windows('slack', false, 1), [])
assert.deepEqual(windows('context', true, 1), ['terminal', 'chrome', 'notes', 'slack'])
assert.deepEqual(windows('weix', true, 2), ['wechat'])
const reordered = ['chatgpt', 'slack', ...MRU0.filter(id => !['chatgpt', 'slack'].includes(id))]
assert.deepEqual(windows('', true, 1, reordered), windows('', true, 1))
const grouped = swRows(windows('', true, 2), 0, 'button', '', true, 2)
assert.equal((grouped.match(/desktop-heading/g) || []).length, 3)
assert.match(grouped, /Desktop 2 · Current/)
assert.match(grouped, /data-i="7"/)
assert.equal((swRows(windows('weix', true, 2), 0, 'button', 'weix', true, 2).match(/desktop-heading/g) || []).length, 1)
assert.ok(!swRows(windows('', false, 1), 0).includes('desktop-heading'))

const { barHTML, sidebarDefaults, settingsForm } = sandbox.search
const emptyGroups = [{ id: 'u', name: 'Ungrouped', items: [] }, { id: 'c', name: 'Code', items: [] }]
assert.ok(!barHTML(emptyGroups, {}, 'button').includes('data-g="u"'))
assert.ok(barHTML(emptyGroups, {}, 'button').includes('data-g="c"'))
assert.ok(!barHTML([{ ...emptyGroups[0], items: ['chrome'] }], {}, 'button',
  { ...sidebarDefaults, showUngrouped: false, showCreateGroup: false }).includes('chrome'))
assert.equal(barHTML([emptyGroups[0]], {}, 'button', { ...sidebarDefaults, showCreateGroup: false }), '')
assert.match(settingsForm(sidebarDefaults), /min="94" max="376" value="188"/)
assert.match(settingsForm(sidebarDefaults), /data-v="hidden"/)
assert.ok(!settingsForm({ ...sidebarDefaults, pos: 'bottom' }).includes('type="range"'))
assert.match(settingsForm({ ...sidebarDefaults, display: 'icon' }), /data-setting="width" disabled/)
assert.ok(!settingsForm({ ...sidebarDefaults, page: 'general' }).includes('type="range"'))
assert.match(settingsForm({ ...sidebarDefaults, page: 'general', allDesktops: true }), /data-setting="allDesktops" checked/)
assert.match(settingsForm({ ...sidebarDefaults, page: 'shortcuts' }), /⌃⌘B/)
assert.match(settingsForm({ ...sidebarDefaults, page: 'shortcuts', sidebarShortcut: false }), /data-setting="sidebarShortcut" >/)
assert.match(barHTML([{ id: 'c', name: 'Code', items: ['terminal', 'chrome'] }], {}, 'button'), /data-id="terminal"[^>]*aria-current="true"/)
assert.match(barHTML([{ id: 'c', name: 'Code', items: ['terminal', 'chrome'] }], {}, 'button', { ...sidebarDefaults, front: 'chrome' }), /data-id="chrome"[^>]*aria-current="true"/)
assert.ok(!barHTML([{ id: 't', name: 'Team', items: ['slack'] }], {}, 'button').includes('data-id="slack"'))
assert.match(barHTML([{ id: 't', name: 'Team', items: ['slack'] }], {}, 'button', { ...sidebarDefaults, desktop: 2 }), /data-id="slack"/)

// Native radio groups must stay independent between the demo and illustration.
assert.match(settingsForm(sidebarDefaults), /name="demo-pos"/)
assert.match(settingsForm({ ...sidebarDefaults, mock: true }), /name="mock-pos"/)
let change, focused
const settingsState = { ...sidebarDefaults }
vm.runInNewContext(source.slice(source.indexOf("    screen.addEventListener('change'"),
  source.indexOf("    sw.addEventListener('mouseover'")), {
  screen: { addEventListener: (_, callback) => { change = callback },
    querySelector: selector => ({ focus: () => { focused = selector } }) },
  st: settingsState, render() {},
})
change({ target: { matches: () => true, dataset: { k: 'pos', v: 'bottom' } } })
assert.equal(settingsState.pos, 'bottom')
assert.equal(focused, 'input[data-k="pos"][data-v="bottom"]')
change({ target: { matches: () => false, dataset: { setting: 'showUngrouped' }, checked: false } })
assert.equal(settingsState.showUngrouped, false)
assert.equal(focused, 'input[data-setting="showUngrouped"]')
change({ target: { matches: () => false, dataset: { setting: 'allDesktops' }, checked: true } })
assert.equal(settingsState.allDesktops, true)
settingsState.sidebarExpanded = true
change({ target: { matches: () => false, dataset: { setting: 'sidebarShortcut' }, checked: false } })
assert.equal(settingsState.sidebarExpanded, false)

const sidebarState = { sidebarShortcut: true, sidebarExpanded: false, sw: {} }
const pointer = {}, sidebarSandbox = { st: sidebarState, render() {}, bar: { addEventListener: (type, callback) => { pointer[type] = callback } } }
vm.runInNewContext(source.slice(source.indexOf('    const toggleSidebar ='), source.indexOf('    function moveWindow'))
  + 'globalThis.toggle = toggleSidebar', sidebarSandbox)
sidebarSandbox.toggle()
assert.equal(sidebarState.sidebarExpanded, true)
assert.equal(sidebarState.sw, null)
pointer.pointerleave()
assert.equal(sidebarState.sidebarExpanded, true)
pointer.pointerenter(); pointer.pointerleave()
assert.equal(sidebarState.sidebarExpanded, false)
sidebarSandbox.toggle(); sidebarSandbox.toggle()
assert.equal(sidebarState.sidebarExpanded, false)
sidebarState.sidebarShortcut = false
sidebarSandbox.toggle()
assert.equal(sidebarState.sidebarExpanded, false)

// Execute the real key listener so native editing and the held-Option demo cannot regress.
let keydown
const state = { ...sidebarDefaults, sw: { query: 'chr', list: [], sel: 0 }, mru: MRU0 }
vm.runInNewContext(source.slice(source.indexOf("    window.addEventListener('keydown'"),
  source.indexOf("    document.addEventListener('keyup'")), {
  window: { addEventListener: (_, callback) => { keydown = callback } }, st: state,
  switcherWindows, renderSw() {}, render() {}, step() {}, commit() {}, cancel() {}, openSw() {},
  toggleSidebar() { state.sidebarExpanded = !state.sidebarExpanded },
})
function press(key, modifiers = {}) {
  let prevented = false
  keydown({ key, code: 'Key' + key.toUpperCase(), target: { matches: () => true },
    preventDefault() { prevented = true }, stopPropagation() {}, ...modifiers })
  return prevented
}
for (const modifier of ['metaKey', 'ctrlKey']) {
  for (const key of ['a', 'v']) {
    assert.equal(press(key, { [modifier]: true }), false)
    assert.equal(state.sw.query, 'chr')
  }
}
assert.equal(press('x'), false)
assert.equal(press('Backspace'), false)
assert.equal(state.sw.query, 'chr')
assert.equal(press('c', { altKey: true }), true)
assert.equal(state.sw.query, 'chrc')
assert.equal(press('Backspace', { altKey: true }), true)
assert.equal(state.sw.query, 'chr')
assert.equal(press('b', { metaKey: true, ctrlKey: true }), true)
assert.equal(state.sidebarExpanded, true)
state.sw = null
assert.equal(press('Escape'), true)
assert.equal(state.sidebarExpanded, false)
state.sidebarShortcut = false
assert.equal(press('b', { metaKey: true, ctrlKey: true }), false)
console.log('PASS: website search matches app/title terms, ranks results, preserves MRU ties, rejects fuzzy matches, and safely highlights text.')
console.log('PASS: native paste/select-all/editing, held-Option input, sidebar visibility, and width settings.')
console.log('PASS: pinyin app/title search and highlights, desktop grouping and ordering, active window highlight, sidebar shortcut and hover dismissal.')
