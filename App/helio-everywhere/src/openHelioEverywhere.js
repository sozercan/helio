const EXCLUDED_PATH_PREFIXES = [
  '/prefs/apps',
  '/api/v1/authorize',
  '/api/v1/authorize.compact',
  '/login',
  '/register',
  '/account/login',
  '/account/register',
  '/account/sso',
  '/auth',
]

const EXCLUDED_REDDIT_SUBDOMAINS = new Set([
  'accounts',
  'ads',
  'business',
  'events',
  'gql',
  'gql-fed',
  'i',
  'oauth',
  'out',
  'preview',
  'sh',
  'ssl',
  'support',
  'v',
])

function isRedirectableRedditHost(hostname) {
  const lower = (hostname || '').toLowerCase()
  if (lower === 'reddit.com') {
    return true
  }
  if (!lower.endsWith('.reddit.com')) {
    return false
  }
  const sub = lower.slice(0, -'.reddit.com'.length)
  if (!sub || sub.includes('.') || EXCLUDED_REDDIT_SUBDOMAINS.has(sub)) {
    return false
  }
  return /^[a-z0-9-]+$/.test(sub)
}

function isBareReddItHost(hostname) {
  return (hostname || '').toLowerCase() === 'redd.it'
}

function buildHelioRedirectURL(rawUrl) {
  let url
  try {
    url = new URL(rawUrl)
  } catch {
    return null
  }

  if (url.protocol !== 'http:' && url.protocol !== 'https:') {
    return null
  }

  if (url.username || url.password || url.port) {
    return null
  }

  if (isBareReddItHost(url.hostname)) {
    const segments = url.pathname.split('/').filter(Boolean)
    if (segments.length !== 1 || !/^[a-z0-9]+$/i.test(segments[0])) {
      return null
    }
    return `helioapp://reddit.com/comments/${segments[0]}${url.search}${url.hash}`
  }

  if (!isRedirectableRedditHost(url.hostname)) {
    return null
  }

  const lowerPath = url.pathname.toLowerCase()
  if (EXCLUDED_PATH_PREFIXES.some((prefix) => lowerPath === prefix || lowerPath.startsWith(`${prefix}/`))) {
    return null
  }

  return `helioapp://reddit.com${url.pathname}${url.search}${url.hash}`
}

if (typeof browser !== 'undefined' && browser.webNavigation?.onBeforeNavigate) {
  browser.webNavigation.onBeforeNavigate.addListener((details) => {
    if (details.frameId !== 0 || details.tabId == null) {
      return
    }

    const redirectUrl = buildHelioRedirectURL(details.url)
    if (!redirectUrl) {
      return
    }

    browser.tabs.update(details.tabId, { url: redirectUrl })
  })
}
