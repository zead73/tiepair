/* The 3D table of the VR mode: the cards of the game as objects lying on a felt board. The
   game (Pascal) says where every card is and what it is (TCVR.table(), see
   TVrPanel.TableSnapshot); this file only draws that, and tells vr.js which card a laser is
   pointing at. Nothing here knows the rules. The board is a Group in the game's own pixel
   layout, scaled by K metres per pixel. */
import * as THREE from './vendor/three.module.min.js?v=__BUILD__';

const K = 0.00135;                         // metres per game pixel (a card is about 0.11 m wide)
const SUITS = ['clubs', 'diamonds', 'hearts', 'spades'];
const BASE = 22;                           // where the slots start in the snapshot
const SLOTS = 29;                          // 0..27 the pyramid, 28 the waste (29 = the stock, for taps)
const PER = 11;                            // numbers per slot in the snapshot (see TVrPanel.TableSnapshot)
const PEEK = BASE + SLOTS * PER;           // Seer's eye: three more cards, six numbers each
const STOCK = 29;

function hex(n) { return '#' + ('000000' + n.toString(16)).slice(-6); }
function rgb(n) { return [(n >> 16) & 255, (n >> 8) & 255, n & 255]; }

// a soft dark blob for the shadows, a golden glow for hints: made once, shared
function softTexture(inner, outer) {
  const c = document.createElement('canvas');
  c.width = c.height = 128;
  const g = c.getContext('2d');
  const gr = g.createRadialGradient(64, 64, 8, 64, 64, 64);
  gr.addColorStop(0, inner);
  gr.addColorStop(1, outer);
  g.fillStyle = gr;
  g.fillRect(0, 0, 128, 128);
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  return t;
}

export function createTable(bridge, glue, renderer) {
  const group = new THREE.Group();
  const planeGeo = new THREE.PlaneGeometry(1, 1);
  const maxAniso = Math.min(8, renderer.capabilities.getMaxAnisotropy());
  const faceTex = new Map();
  let backTex = null, backCanvas = null;
  const markTex = [null, null, null, null];
  const shadowTex = softTexture('rgba(0,0,0,0.55)', 'rgba(0,0,0,0)');
  const glowTex = softTexture('rgba(255,215,120,0.95)', 'rgba(255,200,90,0)');

  // the felt
  const clothMat = new THREE.MeshBasicMaterial({ color: 0xffffff });
  const cloth = new THREE.Mesh(planeGeo, clothMat);
  cloth.position.z = -0.001;
  group.add(cloth);
  let clothKey = '', areaKey = '';

  // red flash (a missed move) and the fade to black, laid over the cloth and cards
  const flashMat = new THREE.MeshBasicMaterial({ color: 0xbe0a14, transparent: true, opacity: 0, depthTest: false });
  const flash = new THREE.Mesh(planeGeo, flashMat);
  flash.position.z = 0.05;
  flash.renderOrder = 50;
  flash.visible = false;
  group.add(flash);
  const dimMat = new THREE.MeshBasicMaterial({ color: 0x000000, transparent: true, opacity: 0, depthTest: false });
  const dim = new THREE.Mesh(planeGeo, dimMat);
  dim.position.z = 0.051;
  dim.renderOrder = 51;
  dim.visible = false;
  group.add(dim);

  function faceTexture(key) {
    let t = faceTex.get(key);
    if (!t) {
      const img = glue.getImage('card_' + SUITS[(key / 13) | 0] + '_' + ('0' + (key % 13 + 1)).slice(-2));
      t = new THREE.Texture(img);
      t.colorSpace = THREE.SRGBColorSpace;
      t.anisotropy = maxAniso;
      t.generateMipmaps = true;
      t.minFilter = THREE.LinearMipmapLinearFilter;
      t.needsUpdate = true;
      faceTex.set(key, t);
    }
    return t;
  }

  function backTexture() {
    const cv = bridge.back();
    if (cv !== backCanvas) {
      backCanvas = cv;
      if (backTex) backTex.dispose();
      backTex = new THREE.CanvasTexture(cv);
      backTex.colorSpace = THREE.SRGBColorSpace;
      backTex.anisotropy = maxAniso;
      backTex.generateMipmaps = true;
      backTex.minFilter = THREE.LinearMipmapLinearFilter;
    }
    return backTex;
  }

  function markTexture(k) {
    if (!markTex[k]) {
      const t = new THREE.CanvasTexture(bridge.mark(k));
      t.colorSpace = THREE.SRGBColorSpace;
      markTex[k] = t;
    }
    return markTex[k];
  }

  // a card: shadow, glow, face and mark, in one Group
  function makeCard(slot) {
    const root = new THREE.Group();
    const shadow = new THREE.Mesh(planeGeo, new THREE.MeshBasicMaterial({ map: shadowTex, transparent: true, depthWrite: false }));
    shadow.position.set(0.045, -0.06, -0.0012);
    shadow.scale.set(1.35, 1.25, 1);
    const glow = new THREE.Mesh(planeGeo, new THREE.MeshBasicMaterial({ map: glowTex, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending }));
    glow.position.z = -0.0006;
    glow.scale.set(1.5, 1.4, 1);
    glow.visible = false;
    const face = new THREE.Mesh(planeGeo, new THREE.MeshBasicMaterial({ transparent: true, alphaTest: 0.5 }));
    face.userData.slot = slot;
    const mark = new THREE.Mesh(planeGeo, new THREE.MeshBasicMaterial({ transparent: true, depthWrite: false }));
    mark.position.z = 0.0004;
    mark.visible = false;
    root.add(shadow, glow, face, mark);
    group.add(root);
    return { root, shadow, glow, face, mark, base: 0 };
  }
  const cards = [];
  for (let i = 0; i < SLOTS; i++) cards.push(makeCard(i));
  // the stock: a few backs piled up, tapped as one
  const stockCards = [makeCard(STOCK), makeCard(STOCK), makeCard(STOCK)];
  const peekCards = [makeCard(-1), makeCard(-1), makeCard(-1)];       // Seer's eye: the next three stock cards (not tappable)
  const pickables = cards.slice(0, 29).map(c => c.face).concat(stockCards.map(c => c.face));

  let hover = -1, t0 = 0;

  function paintCloth(s) {
    const [c0, c1, c2, c3] = [s[8], s[9], s[10], s[11]];
    const aw = s[3] - s[1], ah = s[4] - s[2];
    const key = [c0, c1, c2, c3, aw, ah].join(',');
    if (key === clothKey) return;
    clothKey = key;
    const W = 1024, H = Math.max(64, Math.round(1024 * ah / aw));
    const cv = document.createElement('canvas');
    cv.width = W; cv.height = H;
    const g = cv.getContext('2d');
    const a = rgb(c0), b = rgb(c1);
    g.save();
    g.translate(W / 2, H / 2);
    g.scale(W / 2, H / 2);
    const gr = g.createRadialGradient(0, 0, 0, 0, 0, Math.SQRT2);
    for (let i = 0; i <= 10; i++) {
      const d = i / 10, t = Math.pow(Math.min(1, d * 1.15), 1.7);
      gr.addColorStop(d, 'rgb(' + [0, 1, 2].map(j => Math.round(a[j] + (b[j] - a[j]) * t)).join(',') + ')');
    }
    g.fillStyle = gr;
    g.fillRect(-1, -1, 2, 2);
    g.restore();
    const m = 14;
    g.strokeStyle = hex(c2); g.lineWidth = 3; g.strokeRect(m, m, W - 2 * m, H - 2 * m);
    g.strokeStyle = hex(c3); g.lineWidth = 1.5; g.strokeRect(m + 14, m + 14, W - 2 * (m + 14), H - 2 * (m + 14));
    g.fillStyle = hex(c2);
    for (const [x, y] of [[m, m], [W - m, m], [m, H - m], [W - m, H - m]]) {
      g.beginPath(); g.moveTo(x, y - 9); g.lineTo(x + 9, y); g.lineTo(x, y + 9); g.lineTo(x - 9, y); g.closePath(); g.fill();
    }
    if (clothMat.map) clothMat.map.dispose();
    clothMat.map = new THREE.CanvasTexture(cv);
    clothMat.map.colorSpace = THREE.SRGBColorSpace;
    clothMat.map.anisotropy = maxAniso;
    clothMat.needsUpdate = true;
  }

  // Puts everything where the snapshot says. Returns false when there is nothing to show.
  function update(s, time) {
    if (!s) { group.visible = false; return false; }
    group.visible = true;
    const left = s[1], top = s[2], aw = s[3] - s[1], ah = s[4] - s[2];
    const cx = left + aw / 2, cy = top + ah / 2;
    paintCloth(s);
    cloth.scale.set(aw * K, ah * K, 1);
    for (const o of [flash, dim]) o.scale.set(aw * K * 1.02, ah * K * 1.02, 1);
    flash.visible = s[5] > 0.01; flashMat.opacity = Math.min(0.7, s[5] * 0.7);
    dim.visible = s[6] > 0.01; dimMat.opacity = Math.min(1, s[6]);
    const back = backTexture();
    const pulse = 0.55 + 0.45 * Math.sin(time * 0.004);

    function put(c, l, t, r, b, z, sq) {
      c.root.position.set(((l + r) / 2 - cx) * K, -((t + b) / 2 - cy) * K, z);
      c.root.scale.set((r - l) * K * sq, (b - t) * K, 1);
    }
    for (let slot = 0; slot < SLOTS; slot++) {
      const c = cards[slot], i = BASE + slot * PER;
      if (!s[i]) { c.root.visible = false; continue; }
      c.root.visible = true;
      const picked = s[i + 7] === 2;
      const lift = (slot === hover || picked) ? 0.012 : 0;
      put(c, s[i + 1], s[i + 2], s[i + 3], s[i + 4], 0.0035 + slot * 0.0007 + lift, Math.max(0.02, s[i + 9]));
      const sc = (slot === hover) ? 1.05 : 1;
      c.root.scale.multiplyScalar(1); c.root.scale.x *= sc; c.root.scale.y *= sc;
      const mat = c.face.material;
      mat.map = s[i + 6] ? faceTexture(s[i + 5]) : back;
      mat.color.setScalar(s[i + 10] ? 0.62 : (slot === hover ? 1.2 : 1));       // a card that cannot be taken yet is dimmed
      c.glow.visible = !!s[i + 7];
      if (s[i + 7]) c.glow.material.opacity = picked ? 1 : pulse;
      const mk = s[i + 8];
      c.mark.visible = mk > 0;
      if (mk > 0) c.mark.material.map = markTexture(mk);
    }
    // the stock
    const n = s[17] === 1 ? 3 : (s[17] === 2 ? 1 : 0);          // 2: empty, but it can be turned over again (a faint card to tap)
    for (let k = 0; k < 3; k++) {
      const c = stockCards[k];
      c.root.visible = k < n;
      if (k >= n) continue;
      const lift = (hover === STOCK && k === n - 1) ? 0.012 : 0;
      put(c, s[18], s[19], s[20], s[21], 0.0025 + k * 0.0012 + lift, 1);
      c.face.material.map = back;
      c.face.material.opacity = s[17] === 2 ? 0.35 : 1;
      c.face.material.color.setScalar(hover === STOCK ? 1.15 : 1);
      c.glow.visible = !!s[13] && k === n - 1;
      if (c.glow.visible) c.glow.material.opacity = pulse;
      c.mark.visible = false;
    }
    // Seer's eye
    for (let k = 0; k < 3; k++) {
      const c = peekCards[k], i = PEEK + k * 6;
      c.root.visible = !!s[i];
      if (!s[i]) continue;
      put(c, s[i + 1], s[i + 2], s[i + 3], s[i + 4], 0.003 + (2 - k) * 0.0006, 1);
      c.face.material.map = faceTexture(s[i + 5]);
      c.face.material.color.setScalar(1);
      c.glow.visible = false; c.mark.visible = false;
    }
    return true;
  }

  return {
    group,
    // the size of the board in metres, from the last snapshot
    size(s) { return [(s[3] - s[1]) * K, (s[4] - s[2]) * K]; },
    update,
    // the nearest card (or the stock) a ray hits: its slot, or -1
    pick(raycaster) {
      const hits = raycaster.intersectObjects(pickables.filter(m => m.parent && m.parent.visible), false);
      return hits.length ? { slot: hits[0].object.userData.slot, distance: hits[0].distance, point: hits[0].point } : null;
    },
    setHover(slot) { hover = slot; }
  };
}
