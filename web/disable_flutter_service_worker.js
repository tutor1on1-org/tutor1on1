(() => {
  'use strict';

  const legacyFlutterCaches = [
    'flutter-app-manifest',
    'flutter-temp-cache',
    'flutter-app-cache',
  ];

  async function removeLegacyFlutterOfflineState() {
    if ('caches' in window) {
      await Promise.all(
        legacyFlutterCaches.map((cacheName) => caches.delete(cacheName)),
      );
    }

    if ('serviceWorker' in navigator) {
      // The base href may be release-specific; remove the stable first-level
      // app scope (/app/ or /agent/) and any child-scope worker.
      const basePath = new URL(document.baseURI).pathname;
      const appSegment = basePath.split('/').find((part) => part.length > 0);
      const stableScopePath = appSegment ? `/${appSegment}/` : '/';
      const appScope = new URL(stableScopePath, window.location.origin).href;
      const registrations = await navigator.serviceWorker.getRegistrations();
      await Promise.all(
        registrations
          .filter((registration) => registration.scope.startsWith(appScope))
          .map((registration) => registration.unregister()),
      );
    }
  }

  let flutterLoadStarted = false;
  let fallbackHandle;
  function loadFlutter() {
    if (flutterLoadStarted) {
      return;
    }
    flutterLoadStarted = true;
    window.clearTimeout(fallbackHandle);
    const script = document.createElement('script');
    script.src = 'flutter_bootstrap.js';
    script.async = true;
    document.body.appendChild(script);
  }

  // Browser storage APIs can remain pending during headless startup; never let
  // best-effort legacy cleanup prevent the network-only application from booting.
  fallbackHandle = window.setTimeout(loadFlutter, 3000);
  removeLegacyFlutterOfflineState()
    .catch((error) => {
      console.warn('Could not remove legacy Flutter offline state.', error);
    })
    .finally(loadFlutter);
})();
