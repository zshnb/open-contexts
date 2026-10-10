const assert = require('node:assert/strict')
const fs = require('node:fs')
const vm = require('node:vm')
const path = require('node:path')

const source = fs.readFileSync(path.join(__dirname, '../website/assets/site.js'), 'utf8')
const sandbox = {
  document: { currentScript: { src: '/assets/site.js' }, documentElement: { lang: 'en' } },
}
vm.runInNewContext(source.slice(0, source.indexOf('  const seg ='))
  + 'globalThis.search = { searchWindows, highlight, MRU0, APPS }; })()', sandbox)
const { searchWindows, highlight, MRU0, APPS } = sandbox.search
const results = query => Array.from(searchWindows(MRU0, query))

assert.deepEqual(results(''), Array.from(MRU0))
assert.deepEqual(results('   '), Array.from(MRU0))
assert.deepEqual(results('CHROME'), ['chrome'])
assert.deepEqual(results('chr context'), ['chrome'])
assert.deepEqual(results('  context   chr  '), ['chrome'])
assert.deepEqual(results('gchr'), [])
assert.deepEqual(results('chr missing'), [])
assert.deepEqual(results('no such window'), [])
assert.equal(results('chatgpt')[0], 'chatgpt')
assert.deepEqual(results('context'), ['terminal', 'chrome', 'slack'])
assert.equal(highlight('Google Chrome', 'chr context'), 'Google <mark>Chr</mark>ome')
assert.equal(highlight('Google Chrome', 'ch hro'), 'Google <mark>Chro</mark>me')
assert.equal(highlight('Google Chrome', ''), 'Google Chrome')
assert.equal(highlight('<img>&"', '<img>'), '<mark>&lt;img&gt;</mark>&amp;&quot;')
assert.equal(highlight('Google Chrome', '.*'), 'Google Chrome')
APPS.exact = { name: 'Context', title: 'Example' }
assert.equal(searchWindows([...MRU0, 'exact'], 'context')[0], 'exact')
console.log('PASS: website search matches app/title terms, ranks results, preserves MRU ties, rejects fuzzy matches, and safely highlights text.')
