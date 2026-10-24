/* The few browser things the Pascal code asks for by name: loading the pictures,
   playing a sound from WAV bytes, and asking the browser to keep our saved
   data. Plain JavaScript, no libraries. */
var TCGlue = (function () {
  'use strict';
  var images = {};
  var audio = { ctx: null, bufs: {} };

  function loadImages(pairs, done) {
    // pairs = [key1, url1, key2, url2, ...]
    var total = pairs.length / 2, left = total;
    function finished() { left -= 1; if (left <= 0) done(); }
    if (total === 0) { done(); return; }
    for (var i = 0; i < pairs.length; i += 2) {
      (function (key, url) {
        var img = new Image();
        img.onload = finished;
        img.onerror = function () { if (window.console) console.error('picture failed to load: ' + url); finished(); };
        img.src = url;
        images[key] = img;
      })(pairs[i], pairs[i + 1]);
    }
  }

  function getImage(key) { return images[key]; }

  function getStory() { return window.TC_STORY || ''; }

  function audioContext() {
    if (!audio.ctx) {
      var C = window.AudioContext || window.webkitAudioContext;
      if (!C) return null;
      try { audio.ctx = new C(); } catch (e) { return null; }
    }
    return audio.ctx;
  }

  // Phones and tablets only allow sound after a tap: call this from one.
  function unlockAudio() {
    var ctx = audioContext();
    if (!ctx) return;
    if (ctx.state === 'suspended') { try { ctx.resume(); } catch (e) { } }
    try {                                   // a silent blip wakes iOS up
      var b = ctx.createBuffer(1, 1, 22050), s = ctx.createBufferSource();
      s.buffer = b; s.connect(ctx.destination); s.start(0);
    } catch (e) { }
  }

  function playWav(name, wav) {
    var ctx = audioContext();
    if (!ctx) return;
    if (ctx.state === 'suspended') { try { ctx.resume(); } catch (e) { } }
    function play(buf) {
      var s = ctx.createBufferSource();
      s.buffer = buf; s.connect(ctx.destination); s.start(0);
    }
    if (audio.bufs[name]) { play(audio.bufs[name]); return; }
    var bytes = new Uint8Array(wav.length);
    for (var i = 0; i < wav.length; i++) bytes[i] = wav.charCodeAt(i) & 255;
    try {
      var p = ctx.decodeAudioData(bytes.buffer, function (buf) { audio.bufs[name] = buf; play(buf); }, function () { });
      if (p && p.catch) p.catch(function () { });
    } catch (e) { }
  }

  function persistStorage() {
    try {
      if (navigator.storage && navigator.storage.persist) navigator.storage.persist();
    } catch (e) { }
  }

  return {
    loadImages: loadImages, getImage: getImage, getStory: getStory,
    unlockAudio: unlockAudio, playWav: playWav, persistStorage: persistStorage
  };
})();
