/* The parlour of the VR mode: a gothic Victorian room built from simple shapes and painted
   textures (no models, nothing downloaded), lit by candles, a fire and the moon. The floor is
   at y = 0 and the player stands at the origin facing -z, so the room moves with the rest of
   the "rig" in vr-main.js. The slope-top table the cards lie on is the `podium`: it is
   built for the player's height (see setHeight) and hidden when the flat panel is shown.
   Everything is cheap for a Quest 2: a handful of lights (none cast shadows), few draw
   calls, textures of 1024 px or less, candle flames as sprites. */
import * as THREE from './vendor/three.module.min.js?v=__BUILD__';

const ROOM = { x0: -3.4, x1: 3.4, z0: -4.8, z1: 2.6, h: 3.5 };
const SLOPE = 48 * Math.PI / 180;           // the same slope as the board in vr-main.js

// ---- painting textures ----
function rng(seed) {                        // small deterministic random numbers, so the room never changes between visits
  let a = seed >>> 0;
  return function () {
    a = (a + 0x6D2B79F5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function canvasTex(w, h, draw, rx, ry) {
  const c = document.createElement('canvas');
  c.width = w; c.height = h;
  draw(c.getContext('2d'), w, h);
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  t.wrapS = t.wrapT = THREE.RepeatWrapping;
  t.repeat.set(rx || 1, ry || 1);
  t.anisotropy = 4;
  return t;
}

function speckle(g, w, h, n, r, alpha) {
  for (let i = 0; i < n; i++) {
    const v = r() < 0.5 ? 0 : 255;
    g.fillStyle = 'rgba(' + v + ',' + v + ',' + v + ',' + (r() * alpha) + ')';
    g.fillRect(r() * w, r() * h, 1 + r() * 2, 1 + r() * 2);
  }
}

function floorTexture() {
  return canvasTex(1024, 1024, function (g, w, h) {
    const r = rng(11);
    const rows = 12, ph = h / rows;
    for (let y = 0; y < rows; y++) {
      let x = -r() * 300;
      while (x < w) {
        const len = 220 + r() * 300;
        const l = 15 + r() * 8, s = 38 + r() * 10;
        g.fillStyle = 'hsl(' + (20 + r() * 8) + ',' + s + '%,' + l + '%)';
        g.fillRect(x, y * ph, len, ph);
        g.strokeStyle = 'rgba(0,0,0,0.55)';
        g.lineWidth = 2;
        g.strokeRect(x, y * ph, len, ph);
        for (let k = 0; k < 9; k++) {                 // the grain
          g.strokeStyle = 'rgba(0,0,0,' + (0.08 + r() * 0.12) + ')';
          g.lineWidth = 1;
          g.beginPath();
          const gy = y * ph + 3 + r() * (ph - 6);
          g.moveTo(x + 2, gy);
          g.bezierCurveTo(x + len * 0.3, gy + (r() - 0.5) * 5, x + len * 0.6, gy + (r() - 0.5) * 5, x + len - 2, gy + (r() - 0.5) * 3);
          g.stroke();
        }
        g.fillStyle = 'rgba(255,200,140,0.05)';
        g.fillRect(x, y * ph, len, ph * 0.3);
        x += len;
      }
    }
    speckle(g, w, h, 1500, r, 0.08);
  }, 3.4, 3.7);
}

function wainscotTexture() {
  return canvasTex(512, 512, function (g, w, h) {
    const r = rng(23);
    g.fillStyle = '#2b150d';
    g.fillRect(0, 0, w, h);
    for (let i = 0; i < 40; i++) {                    // vertical grain
      g.strokeStyle = 'rgba(0,0,0,' + (0.1 + r() * 0.15) + ')';
      g.beginPath(); const x = r() * w; g.moveTo(x, 0); g.lineTo(x + (r() - 0.5) * 8, h); g.stroke();
    }
    const m = 36;                                      // a raised panel
    g.fillStyle = '#3a1c10';
    g.fillRect(m, m, w - 2 * m, h - 2 * m);
    g.strokeStyle = 'rgba(255,190,120,0.35)'; g.lineWidth = 3;
    g.beginPath(); g.moveTo(m, h - m); g.lineTo(m, m); g.lineTo(w - m, m); g.stroke();
    g.strokeStyle = 'rgba(0,0,0,0.7)';
    g.beginPath(); g.moveTo(w - m, m); g.lineTo(w - m, h - m); g.lineTo(m, h - m); g.stroke();
    g.strokeStyle = 'rgba(0,0,0,0.5)'; g.lineWidth = 2;
    g.strokeRect(m + 22, m + 22, w - 2 * m - 44, h - 2 * m - 44);
    speckle(g, w, h, 500, r, 0.06);
  }, 1, 1);
}

function wallpaperTexture() {
  return canvasTex(512, 512, function (g, w, h) {
    g.fillStyle = '#4a1022';
    g.fillRect(0, 0, w, h);
    function ornament(cx, cy, s) {                    // a damask flourish, mirrored left and right
      for (const side of [-1, 1]) {
        g.save();
        g.translate(cx, cy);
        g.scale(side, 1);
        g.fillStyle = '#5c1a2e';
        g.beginPath();
        g.moveTo(0, -s);
        g.bezierCurveTo(s * 0.55, -s * 0.7, s * 0.5, -s * 0.1, s * 0.12, 0);
        g.bezierCurveTo(s * 0.6, s * 0.2, s * 0.45, s * 0.7, 0, s);
        g.bezierCurveTo(s * 0.1, s * 0.45, s * 0.15, s * 0.3, 0, s * 0.18);
        g.bezierCurveTo(s * 0.12, -s * 0.05, s * 0.1, -s * 0.5, 0, -s);
        g.fill();
        g.strokeStyle = 'rgba(210,150,90,0.18)';
        g.lineWidth = 1.5;
        g.stroke();
        g.restore();
      }
      g.fillStyle = 'rgba(210,150,90,0.25)';
      g.beginPath(); g.arc(cx, cy, s * 0.07, 0, 6.3); g.fill();
    }
    ornament(w / 2, h / 2, 190);
    ornament(0, 0, 190); ornament(w, 0, 190); ornament(0, h, 190); ornament(w, h, 190);
    g.fillStyle = 'rgba(210,150,90,0.18)';
    for (const [x, y] of [[w / 2, 0], [w / 2, h], [0, h / 2], [w, h / 2]]) {
      g.beginPath(); g.moveTo(x, y - 16); g.lineTo(x + 10, y); g.lineTo(x, y + 16); g.lineTo(x - 10, y); g.fill();
    }
    speckle(g, w, h, 400, rng(5), 0.05);
  }, 3, 1.1);
}

function plasterTexture() {
  return canvasTex(512, 512, function (g, w, h) {
    g.fillStyle = '#241a26';
    g.fillRect(0, 0, w, h);
    speckle(g, w, h, 3000, rng(31), 0.07);
  }, 4, 4);
}

function stoneTexture() {
  return canvasTex(512, 512, function (g, w, h) {
    const r = rng(41);
    g.fillStyle = '#1b1822';
    g.fillRect(0, 0, w, h);
    const rows = 5, bh = h / rows;
    for (let y = 0; y < rows; y++) {
      let x = -r() * 120;
      while (x < w) {
        const bw = 110 + r() * 110;
        const l = 24 + r() * 10;
        g.fillStyle = 'hsl(' + (260 + r() * 20) + ',' + (8 + r() * 8) + '%,' + l + '%)';
        g.fillRect(x + 3, y * bh + 3, bw - 6, bh - 6);
        g.fillStyle = 'rgba(255,255,255,0.06)';
        g.fillRect(x + 3, y * bh + 3, bw - 6, 8);
        x += bw;
      }
    }
    speckle(g, w, h, 2500, r, 0.1);
  }, 1.4, 1);
}

function rugTexture() {
  return canvasTex(1024, 800, function (g, w, h) {
    g.fillStyle = '#3d0c16';
    g.fillRect(0, 0, w, h);
    const r = rng(53);
    function frame(m, col, lw) { g.strokeStyle = col; g.lineWidth = lw; g.strokeRect(m, m, w - 2 * m, h - 2 * m); }
    frame(14, '#c9a24a', 6);
    frame(40, '#1b0a10', 36);
    // a band of diamonds
    g.fillStyle = '#b8903f';
    for (let x = 60; x < w - 40; x += 44) {
      for (const y of [58, h - 58]) { g.beginPath(); g.moveTo(x, y - 12); g.lineTo(x + 12, y); g.lineTo(x, y + 12); g.lineTo(x - 12, y); g.fill(); }
    }
    for (let y = 100; y < h - 80; y += 44) {
      for (const x of [58, w - 58]) { g.beginPath(); g.moveTo(x, y - 12); g.lineTo(x + 12, y); g.lineTo(x, y + 12); g.lineTo(x - 12, y); g.fill(); }
    }
    frame(86, '#c9a24a', 3);
    g.fillStyle = '#521019';
    g.fillRect(92, 92, w - 184, h - 184);
    g.strokeStyle = 'rgba(201,162,74,0.18)'; g.lineWidth = 2;       // a lattice
    for (let i = -h; i < w; i += 64) { g.beginPath(); g.moveTo(92 + i, 92); g.lineTo(92 + i + h, h - 92); g.stroke(); }
    for (let i = 0; i < w + h; i += 64) { g.beginPath(); g.moveTo(92 + i, 92); g.lineTo(92 + i - h, h - 92); g.stroke(); }
    // the medallion
    for (let k = 5; k >= 1; k--) {
      g.fillStyle = k % 2 ? '#1c3a3f' : '#7a1d28';
      g.beginPath(); g.moveTo(w / 2, h / 2 - k * 62); g.lineTo(w / 2 + k * 100, h / 2); g.lineTo(w / 2, h / 2 + k * 62); g.lineTo(w / 2 - k * 100, h / 2); g.closePath(); g.fill();
      g.strokeStyle = '#c9a24a'; g.lineWidth = 3; g.stroke();
    }
    speckle(g, w, h, 5000, r, 0.1);
  }, 1, 1);
}

function curtainTexture() {
  return canvasTex(256, 512, function (g, w, h) {
    for (let x = 0; x < w; x++) {
      const v = 0.5 + 0.5 * Math.sin(x / w * Math.PI * 9);
      g.fillStyle = 'rgb(' + Math.round(60 + 55 * v) + ',' + Math.round(8 + 8 * v) + ',' + Math.round(22 + 16 * v) + ')';
      g.fillRect(x, 0, 1, h);
    }
    const gr = g.createLinearGradient(0, 0, 0, h);
    gr.addColorStop(0, 'rgba(0,0,0,0)'); gr.addColorStop(1, 'rgba(0,0,0,0.5)');
    g.fillStyle = gr; g.fillRect(0, 0, w, h);
  }, 1, 1);
}

function flameTexture() {
  return canvasTex(64, 128, function (g, w, h) {
    const gr = g.createRadialGradient(32, 84, 2, 32, 76, 52);
    gr.addColorStop(0, 'rgba(255,250,220,1)');
    gr.addColorStop(0.25, 'rgba(255,200,90,0.95)');
    gr.addColorStop(0.6, 'rgba(255,120,30,0.45)');
    gr.addColorStop(1, 'rgba(255,60,0,0)');
    g.fillStyle = gr;
    g.beginPath();
    g.moveTo(32, 4);
    g.bezierCurveTo(52, 50, 58, 78, 32, 124);
    g.bezierCurveTo(6, 78, 12, 50, 32, 4);
    g.fill();
  }, 1, 1);
}

function glowTexture(inner, outer) {
  return canvasTex(128, 128, function (g, w, h) {
    const gr = g.createRadialGradient(64, 64, 0, 64, 64, 64);
    gr.addColorStop(0, inner); gr.addColorStop(1, outer);
    g.fillStyle = gr; g.fillRect(0, 0, w, h);
  }, 1, 1);
}

// ---- the room ----
export function createRoom(bridge, glue, renderer) {
  const group = new THREE.Group();
  const podium = new THREE.Group();       // the slope-top table and what stands beside it
  group.add(podium);
  const box = new THREE.BoxGeometry(1, 1, 1);
  const plane = new THREE.PlaneGeometry(1, 1);
  const lamb = (c, o) => new THREE.MeshLambertMaterial(Object.assign({ color: c }, o || {}));
  const wood = lamb(0x2b1710);
  const darkWood = lamb(0x1d0f0a);
  const gold = lamb(0xc9a24a, { emissive: 0x3a2a08 });
  const flames = [];                       // sprites that flicker: {sprite, base, phase}

  function add(parent, geo, mat, x, y, z, sx, sy, sz) {
    const m = new THREE.Mesh(geo, mat);
    m.position.set(x, y, z);
    if (sx !== undefined) m.scale.set(sx, sy, sz);
    parent.add(m);
    return m;
  }

  // lights: a few, none with shadows
  group.add(new THREE.HemisphereLight(0x8a7aa8, 0x2a1a22, 1.15));
  const chandLight = new THREE.PointLight(0xffb464, 26, 11, 2);
  chandLight.position.set(0, 2.5, -1.2);
  group.add(chandLight);
  const fireLight = new THREE.PointLight(0xff7a2c, 18, 8, 2);
  fireLight.position.set(ROOM.x1 - 1.0, 0.7, -1.6);
  group.add(fireLight);
  const moonLight = new THREE.PointLight(0x7f9cff, 7, 7, 2);
  moonLight.position.set(0, 2.0, ROOM.z0 + 0.8);
  group.add(moonLight);

  // floor, rug, ceiling
  const floorMat = new THREE.MeshLambertMaterial({ map: floorTexture() });
  add(group, plane, floorMat, 0, 0, (ROOM.z0 + ROOM.z1) / 2, ROOM.x1 - ROOM.x0, ROOM.z1 - ROOM.z0, 1).rotation.x = -Math.PI / 2;
  add(group, plane, new THREE.MeshLambertMaterial({ map: rugTexture() }), 0, 0.004, -1.25, 3.6, 2.8, 1).rotation.x = -Math.PI / 2;
  const ceil = add(group, plane, new THREE.MeshLambertMaterial({ map: plasterTexture() }), 0, ROOM.h, (ROOM.z0 + ROOM.z1) / 2, ROOM.x1 - ROOM.x0, ROOM.z1 - ROOM.z0, 1);
  ceil.rotation.x = Math.PI / 2;
  for (const z of [-4.0, -2.4, -0.8, 0.8, 2.2]) add(group, box, darkWood, 0, ROOM.h - 0.1, z, ROOM.x1 - ROOM.x0, 0.2, 0.22);
  for (const x of [-2.2, 0, 2.2]) add(group, box, darkWood, x, ROOM.h - 0.1, (ROOM.z0 + ROOM.z1) / 2, 0.22, 0.2, ROOM.z1 - ROOM.z0);

  // walls: wainscot below, wallpaper above, a rail and a cornice between and above
  const wainMat = new THREE.MeshLambertMaterial({ map: wainscotTexture() });
  const paperMat = new THREE.MeshLambertMaterial({ map: wallpaperTexture() });
  const wH = 1.05, uH = ROOM.h - wH;
  function wall(cx, cz, len, rotY) {
    const g = new THREE.Group();
    g.position.set(cx, 0, cz);
    g.rotation.y = rotY;
    const lower = add(g, plane, wainMat, 0, wH / 2, 0, len, wH, 1);
    lower.material = wainMat.clone();
    lower.material.map = wainMat.map.clone();
    lower.material.map.needsUpdate = true;
    lower.material.map.repeat.set(len / 1.05, 1);
    const upper = add(g, plane, paperMat.clone(), 0, wH + uH / 2, 0, len, uH, 1);
    upper.material.map = paperMat.map.clone();
    upper.material.map.needsUpdate = true;
    upper.material.map.repeat.set(len / 1.2, uH / 1.2);
    add(g, box, wood, 0, wH, 0.03, len, 0.08, 0.07);                // the dado rail
    add(g, box, wood, 0, ROOM.h - 0.07, 0.05, len, 0.14, 0.1);       // the cornice
    add(g, box, wood, 0, 0.07, 0.03, len, 0.14, 0.05);               // the skirting
    group.add(g);
    return g;
  }
  const farWall = wall(0, ROOM.z0, ROOM.x1 - ROOM.x0, 0);
  const backWall = wall(0, ROOM.z1, ROOM.x1 - ROOM.x0, Math.PI);
  const leftWall = wall(ROOM.x0, (ROOM.z0 + ROOM.z1) / 2, ROOM.z1 - ROOM.z0, Math.PI / 2);
  const rightWall = wall(ROOM.x1, (ROOM.z0 + ROOM.z1) / 2, ROOM.z1 - ROOM.z0, -Math.PI / 2);
  void farWall; void backWall; void leftWall; void rightWall;

  // candle flames: one shared texture, additive
  const flameTex = flameTexture();
  function flame(parent, x, y, z, size) {
    const s = new THREE.Sprite(new THREE.SpriteMaterial({ map: flameTex, blending: THREE.AdditiveBlending, depthWrite: false, transparent: true }));
    s.position.set(x, y, z);
    s.scale.set(size * 0.55, size, 1);
    parent.add(s);
    flames.push({ s: s, base: size, phase: Math.random() * 6.28 });
    return s;
  }
  const brass = lamb(0xb08a3a, { emissive: 0x2a1c05 });
  const wax = lamb(0xe8dcc0, { emissive: 0x403828 });
  function candle(parent, x, y, z, h) {
    add(parent, new THREE.CylinderGeometry(0.012, 0.012, h, 8), wax, x, y + h / 2, z);
    flame(parent, x, y + h + 0.035, z, 0.07);
  }
  function candelabra(parent, x, z, hgt, arms) {                      // a floor-standing one
    const c = new THREE.Group();
    c.position.set(x, 0, z);
    add(c, new THREE.CylinderGeometry(0.16, 0.2, 0.05, 16), brass, 0, 0.025, 0);
    add(c, new THREE.CylinderGeometry(0.025, 0.04, hgt, 10), brass, 0, hgt / 2, 0);
    add(c, new THREE.SphereGeometry(0.05, 10, 8), brass, 0, hgt * 0.45, 0);
    for (let i = 0; i < arms; i++) {
      const a = (i / arms) * Math.PI * 2, rx = Math.cos(a) * 0.17, rz = Math.sin(a) * 0.17;
      add(c, new THREE.CylinderGeometry(0.008, 0.008, 0.17, 6), brass, rx / 2, hgt - 0.02, rz / 2).rotation.set(rz > 0 ? -1.3 : 1.3, 0, 0);
      add(c, new THREE.CylinderGeometry(0.03, 0.02, 0.03, 10), brass, rx, hgt + 0.02, rz);
      candle(c, rx, hgt + 0.035, rz, 0.1 + 0.03 * (i % 3));
    }
    add(c, new THREE.CylinderGeometry(0.03, 0.02, 0.03, 10), brass, 0, hgt + 0.02, 0);
    candle(c, 0, hgt + 0.035, 0, 0.16);
    parent.add(c);
  }

  // the chandelier
  {
    const c = new THREE.Group();
    c.position.set(0, 2.6, -1.2);
    add(c, new THREE.TorusGeometry(0.5, 0.025, 8, 36), brass, 0, 0, 0).rotation.x = Math.PI / 2;
    add(c, new THREE.TorusGeometry(0.28, 0.015, 8, 28), brass, 0, 0.05, 0).rotation.x = Math.PI / 2;
    add(c, new THREE.CylinderGeometry(0.008, 0.008, 0.9, 6), brass, 0, 0.45, 0);
    add(c, new THREE.SphereGeometry(0.06, 10, 8), brass, 0, -0.1, 0);
    for (let i = 0; i < 8; i++) {
      const a = i / 8 * Math.PI * 2;
      candle(c, Math.cos(a) * 0.5, 0.01, Math.sin(a) * 0.5, 0.12);
    }
    group.add(c);
  }

  // the fireplace in the middle of the far wall, with the portraits over it
  {
    const f = new THREE.Group();
    f.position.set(ROOM.x1 - 0.3, 0, -1.6);          // on the right wall: you turn your head to see it
    f.rotation.y = -Math.PI / 2;
    const stone = new THREE.MeshLambertMaterial({ map: stoneTexture() });
    add(f, box, stone, -0.95, 0.75, 0, 0.5, 1.5, 0.6);
    add(f, box, stone, 0.95, 0.75, 0, 0.5, 1.5, 0.6);
    add(f, box, stone, 0, 1.4, 0, 2.4, 0.3, 0.6);
    add(f, box, new THREE.MeshBasicMaterial({ color: 0x050306 }), 0, 0.62, -0.1, 1.4, 1.25, 0.2);
    add(f, box, stone, 0, 0.04, 0.15, 2.4, 0.08, 0.9);                       // the hearth
    add(f, box, wood, 0, 1.6, 0.08, 2.9, 0.12, 0.8);                          // the mantel shelf
    for (const x of [-0.25, 0.25]) add(f, new THREE.CylinderGeometry(0.1, 0.1, 0.1, 12), wood, x, 0.2, -0.1).rotation.z = Math.PI / 2;
    // the fire
    const fireTex = flameTex;
    for (let i = 0; i < 5; i++) {
      const s = new THREE.Sprite(new THREE.SpriteMaterial({ map: fireTex, blending: THREE.AdditiveBlending, depthWrite: false, transparent: true }));
      s.position.set(-0.4 + i * 0.2, 0.42, 0.05);
      s.scale.set(0.38, 0.6 + (i % 2) * 0.2, 1);
      f.add(s);
      flames.push({ s: s, base: s.scale.y, phase: i * 1.7, fire: true });
    }
    add(f, plane, new THREE.MeshBasicMaterial({ map: glowTexture('rgba(255,150,50,0.7)', 'rgba(255,80,0,0)'), transparent: true, blending: THREE.AdditiveBlending, depthWrite: false }), 0, 0.55, 0.35, 2.8, 1.8, 1);
    // candles, a clock and a skull on the mantel
    candle(f, -1.15, 1.66, 0.1, 0.22);
    candle(f, 1.15, 1.66, 0.1, 0.26);
    candle(f, -0.85, 1.66, 0.12, 0.14);
    add(f, box, darkWood, 0.55, 1.78, 0.1, 0.34, 0.26, 0.16);
    add(f, new THREE.CircleGeometry(0.1, 20), new THREE.MeshBasicMaterial({ color: 0xd8cbb0 }), 0.55, 1.8, 0.185);
    add(f, new THREE.SphereGeometry(0.075, 12, 10), lamb(0xcfc6b0), -0.5, 1.72, 0.12);
    // the portraits: the three vampires of the court, in dark frames with brass corners
    function portrait(key, x, y, w) {
      const img = glue.getImage(key);
      if (!img) return;
      const t = new THREE.Texture(img);
      t.colorSpace = THREE.SRGBColorSpace; t.anisotropy = 4; t.needsUpdate = true;
      const h = w * 878 / 596;
      const p = new THREE.Group();
      p.position.set(x, y, 0.3);
      add(p, box, darkWood, 0, 0, -0.02, w + 0.16, h + 0.16, 0.05);
      add(p, box, gold, 0, 0, 0.01, w + 0.05, h + 0.05, 0.02);
      add(p, new THREE.PlaneGeometry(w, h), new THREE.MeshBasicMaterial({ map: t, transparent: true, color: 0xcfc6c0 }), 0, 0, 0.025);
      for (const [cx, cy] of [[-1, -1], [1, -1], [-1, 1], [1, 1]]) add(p, box, brass, cx * (w / 2 + 0.07), cy * (h / 2 + 0.07), 0.03, 0.07, 0.07, 0.02);
      f.add(p);
    }
    portrait('vampire_jack', -1.25, 2.55, 0.62);
    portrait('vampire_king', 0, 2.65, 0.78);
    portrait('vampire_queen', 1.25, 2.55, 0.62);
    group.add(f);
  }

  // the tall window on the right wall, with the moon and curtains
  const windowState = { key: '', mat: null };
  {
    const ww = 1.4, wh = 2.0, wy = 0.8;
    const wg = new THREE.Group();
    wg.position.set(0, 0, ROOM.z0 + 0.01);            // in the middle of the far wall, straight ahead
    const shape = new THREE.Shape();
    shape.moveTo(-ww / 2, wy);
    shape.lineTo(ww / 2, wy);
    shape.lineTo(ww / 2, wy + wh);
    shape.absarc(0, wy + wh, ww / 2, 0, Math.PI, false);
    shape.lineTo(-ww / 2, wy);
    const geo = new THREE.ShapeGeometry(shape, 24);
    const pos = geo.attributes.position, uv = geo.attributes.uv;
    for (let i = 0; i < pos.count; i++) uv.setXY(i, (pos.getX(i) + ww / 2) / ww, (pos.getY(i) - wy) / (wh + ww / 2));
    windowState.mat = new THREE.MeshBasicMaterial({ color: 0xffffff });
    const glass = new THREE.Mesh(geo, windowState.mat);
    glass.position.z = 0.02;
    wg.add(glass);
    const frameShape = new THREE.Mesh(new THREE.ShapeGeometry(shape, 24), darkWood);
    frameShape.scale.set(1.18, 1.07, 1);
    frameShape.position.set(0, -wy * 0.07 - 0.02, 0.01);
    wg.add(frameShape);
    add(wg, box, darkWood, 0, wy + wh / 2, 0.04, 0.05, wh, 0.04);        // mullions
    add(wg, box, darkWood, 0, wy + wh * 0.5, 0.04, ww, 0.05, 0.04);
    add(wg, box, darkWood, 0, wy + wh * 0.8, 0.04, ww, 0.04, 0.04);
    add(wg, box, wood, 0, wy - 0.04, 0.09, ww + 0.3, 0.08, 0.2);         // the sill
    const curtain = new THREE.MeshLambertMaterial({ map: curtainTexture() });
    for (const sx of [-1, 1]) add(wg, plane, curtain, sx * (ww / 2 + 0.28), 1.75, 0.16, 0.55, 3.0, 1);
    add(wg, new THREE.CylinderGeometry(0.02, 0.02, ww + 1.4, 8), brass, 0, 3.2, 0.2).rotation.z = Math.PI / 2;
    group.add(wg);
    // moonlight on the floor: the window's pane laid across the boards
    const beam = add(group, plane, new THREE.MeshBasicMaterial({ map: glowTexture('rgba(150,175,255,0.55)', 'rgba(150,175,255,0)'), transparent: true, blending: THREE.AdditiveBlending, depthWrite: false }), 0, 0.006, ROOM.z0 + 1.7, 2.0, 2.8, 1);
    beam.rotation.set(-Math.PI / 2, 0, 0.1);
  }

  // bookcases on the left wall
  {
    const r = rng(77);
    const bookGeo = new THREE.BoxGeometry(1, 1, 1);
    const bookMat = new THREE.MeshLambertMaterial({ color: 0xffffff });
    const books = new THREE.InstancedMesh(bookGeo, bookMat, 420);
    let n = 0;
    const tmp = new THREE.Object3D(), col = new THREE.Color();
    const palette = [0x5a1620, 0x1d3b2f, 0x2a2a52, 0x4a3320, 0x6b2236, 0x2b4a4a, 0x7a5a28, 0x33202e];
    for (const cz of [-0.7, -2.9]) {
      const c = new THREE.Group();
      c.position.set(ROOM.x0 + 0.22, 0, cz);
      add(c, box, darkWood, -0.18, 1.4, 0, 0.03, 2.8, 1.9);            // the back, against the wall
      add(c, box, wood, 0, 1.4, -0.95, 0.4, 2.8, 0.06);                 // the two ends
      add(c, box, wood, 0, 1.4, 0.95, 0.4, 2.8, 0.06);
      add(c, box, wood, 0, 2.83, 0, 0.46, 0.08, 2.0);                   // the top
      add(c, box, wood, 0.02, 0.1, 0, 0.44, 0.2, 1.96);                 // the plinth
      for (let s = 0; s < 6; s++) {
        const sy = 0.3 + s * 0.46;
        add(c, box, wood, -0.03, sy, 0, 0.34, 0.03, 1.86);
        let z = -0.88;
        while (z < 0.84 && n < 420) {
          const bw = 0.03 + r() * 0.04, bh = 0.26 + r() * 0.12;
          tmp.position.set(c.position.x - 0.03, sy + 0.015 + bh / 2, cz + z + bw / 2);
          tmp.scale.set(0.24, bh, bw);
          tmp.rotation.set(0, 0, 0);
          tmp.updateMatrix();
          books.setMatrixAt(n, tmp.matrix);
          books.setColorAt(n, col.setHex(palette[(r() * palette.length) | 0]).multiplyScalar(0.75 + r() * 0.3));
          n++;
          z += bw + 0.004;
        }
      }
      group.add(c);
    }
    books.count = n;
    books.instanceMatrix.needsUpdate = true;
    books.instanceColor.needsUpdate = true;
    group.add(books);
  }

  // two armchairs by the fire, a lamp table, and a door behind the player
  function armchair(x, z, rotY, color) {
    const c = new THREE.Group();
    c.position.set(x, 0, z);
    c.rotation.y = rotY;
    const velvet = lamb(color);
    add(c, box, velvet, 0, 0.42, 0, 0.7, 0.2, 0.7);
    add(c, box, velvet, 0, 0.95, 0.3, 0.7, 0.95, 0.14).rotation.x = -0.08;
    add(c, box, velvet, -0.4, 0.62, 0, 0.14, 0.3, 0.7);
    add(c, box, velvet, 0.4, 0.62, 0, 0.14, 0.3, 0.7);
    for (const [lx, lz] of [[-0.3, -0.3], [0.3, -0.3], [-0.3, 0.3], [0.3, 0.3]]) add(c, box, darkWood, lx, 0.16, lz, 0.07, 0.32, 0.07);
    add(c, box, brass, 0, 1.45, 0.3, 0.2, 0.06, 0.05);
    group.add(c);
  }
  armchair(2.2, -2.9, -Math.PI / 2 - 0.3, 0x4a1020);           // one by the fire, on its far side, so that it does not stand in front of it
  {
    const t = new THREE.Group();
    t.position.set(3.05, 0, -0.45);                                // a lamp table on the near side of the fire
    add(t, new THREE.CylinderGeometry(0.28, 0.28, 0.04, 20), wood, 0, 0.7, 0);
    add(t, new THREE.CylinderGeometry(0.03, 0.05, 0.7, 10), wood, 0, 0.35, 0);
    add(t, new THREE.CylinderGeometry(0.16, 0.18, 0.03, 16), wood, 0, 0.015, 0);
    candle(t, 0, 0.72, 0, 0.16);
    group.add(t);
  }
  {
    const d = new THREE.Group();                                   // an arched door in the back wall
    d.position.set(0, 0, ROOM.z1 - 0.02);
    d.rotation.y = Math.PI;
    add(d, box, darkWood, 0, 1.15, 0, 1.2, 2.3, 0.08);
    add(d, new THREE.CylinderGeometry(0.6, 0.6, 0.08, 20, 1, false, 0, Math.PI), darkWood, 0, 2.3, 0).rotation.x = Math.PI / 2;
    add(d, box, wood, -0.28, 1.15, 0.05, 0.5, 2.0, 0.03);
    add(d, box, wood, 0.28, 1.15, 0.05, 0.5, 2.0, 0.03);
    add(d, new THREE.SphereGeometry(0.04, 8, 8), brass, 0.5, 1.1, 0.07);
    group.add(d);
  }
  for (const [x, z, ry] of [[-2.0, ROOM.z1 - 0.1, Math.PI], [2.0, ROOM.z1 - 0.1, Math.PI]]) {      // wall sconces behind the player
    const s = new THREE.Group();
    s.position.set(x, 1.9, z);
    s.rotation.y = ry;
    add(s, box, brass, 0, 0, 0, 0.12, 0.2, 0.04);
    add(s, new THREE.CylinderGeometry(0.03, 0.03, 0.04, 8), brass, 0, 0.12, 0.08);
    candle(s, 0, 0.14, 0.08, 0.14);
    group.add(s);
  }

  // beside the table: candelabras on the floor (hidden with the table when the flat panel shows)
  candelabra(podium, 1.1, -1.35, 1.15, 4);
  candelabra(podium, -1.2, -1.45, 1.0, 3);

  // the slope-top table: a cabinet from the floor up to the board's slope
  const cabinetMat = new THREE.MeshLambertMaterial({ map: wainscotTexture() });
  cabinetMat.map.repeat.set(1.5, 1);
  let cabinet = null, trim = null, lastKey = '';
  function setBoard(headY, width, height) {
    const key = [headY.toFixed(2), width.toFixed(2), height.toFixed(2)].join(',');
    if (key === lastKey) return;
    lastKey = key;
    if (cabinet) { podium.remove(cabinet); cabinet.geometry.dispose(); }
    if (trim) { podium.remove(trim); trim.geometry.dispose(); }
    const yc = headY - 0.5, zc = -0.85, hh = height / 2 + 0.07;
    const s = Math.sin(SLOPE), c = Math.cos(SLOPE);
    const nz = zc + hh * c, ny = yc - hh * s;        // the near edge of the slope
    const fz = zc - hh * c, fy = yc + hh * s;        // the far edge
    const dn = 0.012;                                  // a hair under the board, so that the two do not fight
    const sh = new THREE.Shape();
    sh.moveTo(nz, 0); sh.lineTo(fz - 0.04, 0); sh.lineTo(fz - 0.04, fy - dn); sh.lineTo(nz, ny - dn); sh.lineTo(nz, 0);
    const geo = new THREE.ExtrudeGeometry(sh, { depth: width + 0.2, bevelEnabled: false });
    geo.translate(0, 0, -(width + 0.2) / 2);
    geo.rotateY(-Math.PI / 2);                         // the shape's x becomes -z... then flip so that it is (z, y)
    cabinet = new THREE.Mesh(geo, cabinetMat);
    podium.add(cabinet);
    // a brass edge along the top of the slope
    const tg = new THREE.BoxGeometry(width + 0.26, 0.03, 0.03);
    trim = new THREE.Mesh(tg, brass);
    trim.position.set(0, ny + 0.005, nz + 0.01);
    podium.add(trim);
  }

  function setStyle(style) {
    const key = style && style[6] ? style[6] : 'house';
    if (key === windowState.key) return;
    const img = glue.getImage(key) || glue.getImage('house');
    if (!img) return;
    windowState.key = key;
    const t = canvasTex(512, 768, function (g, w, h) {
      // the sky and the moon of the Style picture, as seen from the room
      const sw = img.naturalWidth || img.width, sh = img.naturalHeight || img.height;
      g.drawImage(img, sw * 0.55, 0, sw * 0.42, sh * 0.62, 0, 0, w, h);
      const gr = g.createLinearGradient(0, h * 0.7, 0, h);
      gr.addColorStop(0, 'rgba(10,6,16,0)'); gr.addColorStop(1, 'rgba(10,6,16,0.8)');
      g.fillStyle = gr; g.fillRect(0, 0, w, h);
    }, 1, 1);
    if (windowState.mat.map) windowState.mat.map.dispose();
    windowState.mat.map = t;
    windowState.mat.needsUpdate = true;
  }

  function update(time) {
    const t = time * 0.001;
    for (const f of flames) {
      const j = Math.sin(t * 7.3 + f.phase) * 0.5 + Math.sin(t * 11.9 + f.phase * 1.7) * 0.3 + Math.sin(t * 3.1 + f.phase * 0.6) * 0.2;
      f.s.scale.y = f.base * (1 + 0.1 * j);
      f.s.scale.x = f.base * (f.fire ? 0.62 : 0.55) * (1 - 0.06 * j);
    }
    const sway = Math.sin(t * 2.3) * 0.5 + Math.sin(t * 5.1) * 0.3;
    chandLight.intensity = 26 * (1 + 0.04 * sway);
    fireLight.intensity = 18 * (1 + 0.1 * (Math.sin(t * 6.1) * 0.5 + Math.sin(t * 9.7) * 0.5));
  }

  return { group, podium, setBoard, setStyle, update };
}
