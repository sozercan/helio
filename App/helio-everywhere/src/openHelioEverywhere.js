const EXCLUDED_PATH_PREFIXES = ['/prefs/apps', '/api/v1/authorize']

function isRedirectableRedditHost(hostname) {
  const lower = hostname.toLowerCase()
  return lower === 'reddit.com' || lower === 'www.reddit.com' || lower === 'old.reddit.com' || lower === 'm.reddit.com'
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

  if (!isRedirectableRedditHost(url.hostname)) {
    return null
  }

  if (EXCLUDED_PATH_PREFIXES.some((prefix) => url.pathname.startsWith(prefix))) {
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
