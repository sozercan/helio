const EXCLUDED_PATH_PREFIXES = [
  '/prefs/apps',
  '/api/v1/authorize',
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
  'api',
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

function isExcludedPath(pathname) {
  const lowerPath = (pathname || '').toLowerCase()
  return EXCLUDED_PATH_PREFIXES.some(
    (prefix) => lowerPath === prefix || lowerPath.startsWith(`${prefix}/`) || lowerPath.startsWith(`${prefix}.`),
  )
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

  if (!isRedirectableRedditHost(url.hostname)) {
    return null
  }

  if (isExcludedPath(url.pathname)) {
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
