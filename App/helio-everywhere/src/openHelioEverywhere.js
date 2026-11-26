browser.webNavigation.onBeforeNavigate.addListener(function(details) {
  if (details.frameId === 0) {
    console.log('Navigating to:', details.url);
    
    try {
      var url = new URL(details.url);
      console.log('Parsed URL:', url);

      if (url.hostname.includes('reddit.com')) {
        var newUrl = details.url.replace(/(https?:\/\/)?(www\.)?reddit\.com/gi, 'helioapp://reddit.com');
        console.log('Modified URL:', newUrl);

        browser.webNavigation.onBeforeNavigate.removeListener(listener);
        browser.webNavigation.navigate({ url: newUrl });
      }
    } catch (e) {
      console.error('Invalid URL', details.url, e);
    }
  }
});

var listener = browser.webNavigation.onBeforeNavigate.addListener(function() {});
