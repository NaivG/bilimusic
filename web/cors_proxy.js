// CORS Proxy for Bilibili API
// This script intercepts fetch requests to Bilibili API and proxies them

(function() {
  'use strict';

  const BILI_API_HOST = 'api.bilibili.com';

  // Intercept fetch requests
  const originalFetch = window.fetch;
  window.fetch = async function(url, options = {}) {
    const urlString = typeof url === 'string' ? url : url.url || url.toString();

    // Only proxy requests to Bilibili API
    if (urlString.includes(BILI_API_HOST)) {
      try {
        // Use a CORS proxy - you can replace this with your own proxy
        const proxyUrl = `https://corsproxy.io/?${encodeURIComponent(urlString)}`;
        const response = await originalFetch(proxyUrl, {
          ...options,
          mode: 'cors'
        });
        return response;
      } catch (error) {
        console.error('Proxy fetch failed:', error);
        // Fallback: try direct request
        return originalFetch(url, options);
      }
    }

    return originalFetch(url, options);
  };

  // Also intercept XMLHttpRequest for packages that use it
  const originalXHROpen = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function(method, url, ...rest) {
    const urlString = typeof url === 'string' ? url : '';

    if (urlString.includes(BILI_API_HOST)) {
      // Store original URL for later use
      this._originalUrl = urlString;
      // Modify URL to go through proxy
      url = `https://corsproxy.io/?${encodeURIComponent(urlString)}`;
    }

    return originalXHROpen.call(this, method, url, ...rest);
  };

  console.log('Bilibili CORS Proxy loaded');
})();
