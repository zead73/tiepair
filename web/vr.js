/* The "Enter VR" button of the page. This file is small on purpose: every visitor loads it,
   but the VR code (vr-main.js) and three.js, which are big, are only fetched when the player
   is on a browser that can do VR (or asks for ?vrpreview) and presses the button.
   ?vrpreview shows the VR scene in an ordinary window with the mouse as the pointer;
   ?vrdebug adds a frame-rate line to it and says why VR is missing when it is. */
const PREVIEW = /[?&]vrpreview\b/.test(location.search);
const DEBUG = /[?&]vrdebug\b/.test(location.search);

let main = null;
function load() {
  if (!main) main = import('./vr-main.js?v=__BUILD__');
  return main;
}

async function init() {
  const btn = document.getElementById('btnVr');
  if (!btn) return;
  let ok = false;
  try { ok = !!(navigator.xr && await navigator.xr.isSessionSupported('immersive-vr')); } catch (e) { ok = false; }
  if (ok) {
    btn.style.display = '';
    btn.addEventListener('click', function () {
      btn.textContent = 'Loading VR...';
      load().then(function (m) { return m.startXR(btn); })
        .catch(function (e) { btn.textContent = 'VR failed: ' + (e && e.message ? e.message : e); });
    });
  } else if (PREVIEW) {
    btn.style.display = '';
    btn.textContent = 'VR preview';
    btn.addEventListener('click', function () { load().then(function (m) { m.startPreview(); }); });
  } else if (DEBUG) {                                      // say why there is no VR button
    btn.style.display = '';
    btn.textContent = !window.isSecureContext ? 'VR: page is not a secure context (needs https)'
      : !navigator.xr ? 'VR: this browser has no WebXR'
      : 'VR: immersive-vr is not supported here';
  }
}

// the game makes window.TCVR once its pictures have loaded
(function wait() {
  if (window.TCVR) init();
  else setTimeout(wait, 250);
})();
