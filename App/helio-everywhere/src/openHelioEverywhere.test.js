import assert from 'node:assert/strict'
import fs from 'node:fs'
import test from 'node:test'
import vm from 'node:vm'

const source = fs.readFileSync(new URL('./openHelioEverywhere.js', import.meta.url), 'utf8')
const context = { URL, Set }
vm.runInNewContext(source, context)
const { buildHelioRedirectURL, isBareReddItHost, isRedirectableRedditHost } = context

test('accepts standard, legacy, mobile, np, and language reddit.com subdomains', () => {
  for (const host of ['reddit.com', 'www.reddit.com', 'old.reddit.com', 'new.reddit.com', 'm.reddit.com', 'np.reddit.com', 'de.reddit.com']) {
    assert.equal(isRedirectableRedditHost(host), true, host)
  }
  assert.equal(buildHelioRedirectURL('https://np.reddit.com/r/swift/comments/abc123/title/?sort=new#c1'), 'helioapp://reddit.com/r/swift/comments/abc123/title/?sort=new#c1')
  assert.equal(buildHelioRedirectURL('https://de.reddit.com/r/swift/s/shareToken'), 'helioapp://reddit.com/r/swift/s/shareToken')
})

test('expands bare redd.it short links and rejects media subdomains or bad paths', () => {
  assert.equal(isBareReddItHost('redd.it'), true)
  assert.equal(buildHelioRedirectURL('https://redd.it/abc123'), 'helioapp://reddit.com/comments/abc123')
  assert.equal(buildHelioRedirectURL('https://i.redd.it/abc123.jpg'), null)
  assert.equal(buildHelioRedirectURL('https://v.redd.it/abc123'), null)
  assert.equal(buildHelioRedirectURL('https://preview.redd.it/abc123.png'), null)
  assert.equal(buildHelioRedirectURL('https://redd.it/'), null)
  assert.equal(buildHelioRedirectURL('https://redd.it/a/b'), null)
})

test('rejects excluded auth/media hosts, suffix tricks, credentials, custom ports, and auth paths', () => {
  for (const bad of [
    'https://notreddit.com/r/swift',
    'https://evil.reddit.com.example.com/r/swift',
    'https://a.b.reddit.com/r/swift',
    'https://accounts.reddit.com/api/access_token',
    'https://oauth.reddit.com/r/swift/hot',
    'https://i.reddit.com/pic.jpg',
    'https://user:pass@www.reddit.com/r/swift',
    'https://www.reddit.com:8443/r/swift',
    'https://www.reddit.com/login?next=/r/swift',
    'https://www.reddit.com/PREFS/APPS',
    'https://www.reddit.com/api/v1/authorize?client_id=abc',
    'https://www.reddit.com/api/v1/authorize.compact?client_id=abc',
    'javascript:alert(1)',
  ]) {
    assert.equal(buildHelioRedirectURL(bad), null, bad)
  }
})
