/* VR mode, the heavy part: it is only loaded (by vr.js) when the player is about to use VR.
   In a headset (the Meta Quest browser has WebXR; the page must be https or localhost) the
   game is shown two ways, and the game itself decides which:
     - the cards on the table: a 3D board with the cards lying on it (vr-table.js), in a
       parlour (vr-room.js), with the toolbar and the duel panel as floating signs around it, and
     - anything else (the menu, the Store, story scenes, dialogs, the win picture): the
       whole game on one flat panel in front of you, as drawn by the page's own code.
   The game's Pascal code draws the panel canvas and keeps the rules (window.TCVR, made in
   tiecardsweb.pas); this file only puts things in 3D, turns a laser hit into a tap, and
   keeps the headset's frame loop going. three.js does the 3D (web/vendor). */
import * as THREE from './vendor/three.module.min.js?v=__BUILD__';
import { createTable } from './vr-table.js?v=__BUILD__';
import { createRoom } from './vr-room.js?v=__BUILD__';

const BUILD = '__BUILD__';
const PANEL_WIDTH = 2.4;            // the flat panel, metres
const PANEL_DISTANCE = 1.5;
const SLOPE = 48 * Math.PI / 180;   // how steeply the board rises away from you
const DEBUG = /[?&]vrdebug\b/.test(location.search);
const ROOM_ON = !/[?&]vrroom=0\b/.test(location.search);      // ?vrroom=0 turns the parlour off (a plain dark void)

let renderer = null, scene = null, camera = null, rig = null;
let full = null, texture = null, floor = null;
let board = null, tableGroup = null, hudBar = null, hudSide = null, hudKeys = null, room = null;
let session = null;
let pointers = [];                  // one per controller or hand: {obj, line, dot}
let placed = 0;                     // frames since the session began, until the rig is put in front of you
let headY = 1.2;
let previewEl = null;
let tableMode = false;
const boardSize = [1.33, 0.75];       // the board in metres, from the game's own layout
const raycaster = new THREE.Raycaster();
const tmpMat = new THREE.Matrix4();
const stats = { frames: 0, since: 0 };

function say(btn, text) { if (btn) btn.textContent = text; }

// A plane that shows only the part (x0, y0, w, h) of the panel's canvas, wMetres wide.
function cropPlane(x0, y0, w, h, wMetres) {
  const b = window.TCVR;
  const cw = b.width, ch = b.height;
  const g = new THREE.PlaneGeometry(wMetres, wMetres * h / w);
  const uv = g.attributes.uv;
  for (let i = 0; i < uv.count; i++) {
    uv.setXY(i, (x0 + uv.getX(i) * w) / cw, 1 - (y0 + (1 - uv.getY(i)) * h) / ch);
  }
  const m = new THREE.Mesh(g, new THREE.MeshBasicMaterial({ map: texture, transparent: true, toneMapped: false }));
  return m;
}

function build() {
  const bridge = window.TCVR;
  renderer = new THREE.WebGLRenderer({ antialias: true, alpha: false });
  renderer.setPixelRatio(1);
  renderer.xr.enabled = true;
  renderer.xr.setReferenceSpaceType('local-floor');
  renderer.xr.setFoveation(1);
  scene = new THREE.Scene();
  scene.background = new THREE.Color(0x0d0814);
  camera = new THREE.PerspectiveCamera(70, 1, 0.05, 50);
  rig = new THREE.Group();            // everything that sits "in front of you": moved as one when you recentre
  scene.add(rig);

  texture = new THREE.CanvasTexture(bridge.canvas);
  texture.colorSpace = THREE.SRGBColorSpace;
  texture.minFilter = THREE.LinearFilter;
  texture.magFilter = THREE.LinearFilter;
  texture.generateMipmaps = false;
  texture.anisotropy = 4;

  // the whole game on one flat panel
  full = new THREE.Mesh(
    new THREE.PlaneGeometry(PANEL_WIDTH, PANEL_WIDTH * bridge.height / bridge.width),
    new THREE.MeshBasicMaterial({ map: texture, toneMapped: false }));
  rig.add(full);

  // the 3D table, and the signs around it (the toolbar, the duel panel, Skip/Cancel)
  board = createTable(bridge, window.TCGlue, renderer);
  tableGroup = board.group;
  rig.add(tableGroup);
  hudBar = cropPlane(0, 0, bridge.width, bridge.barHeight, 1.5);
  hudSide = cropPlane(0, bridge.barHeight, 290, bridge.height - bridge.barHeight, 0.5);
  hudKeys = cropPlane(1130, bridge.barHeight, 150, 70, 0.2);
  rig.add(hudBar, hudSide, hudKeys);

  if (ROOM_ON) {
    room = createRoom(bridge, window.TCGlue, renderer);      // the parlour moves with the rig, and so does its table
    rig.add(room.group);
    room.setStyle(bridge.style());
  } else {
    // a dim floor, so that there is a "down" to stand on
    const fc = document.createElement('canvas');
    fc.width = fc.height = 256;
    const g = fc.getContext('2d');
    const grad = g.createRadialGradient(128, 128, 0, 128, 128, 128);
    grad.addColorStop(0, 'rgba(60,40,80,0.9)');
    grad.addColorStop(1, 'rgba(13,8,20,0)');
    g.fillStyle = grad;
    g.fillRect(0, 0, 256, 256);
    floor = new THREE.Mesh(
      new THREE.CircleGeometry(4, 48),
      new THREE.MeshBasicMaterial({ map: new THREE.CanvasTexture(fc), transparent: true }));
    floor.rotation.x = -Math.PI / 2;
    scene.add(floor);
  }

  // the laser pointers
  for (let i = 0; i < 2; i++) {
    const obj = renderer.xr.getController(i);
    const line = new THREE.Line(
      new THREE.BufferGeometry().setFromPoints([new THREE.Vector3(0, 0, 0), new THREE.Vector3(0, 0, -1)]),
      new THREE.LineBasicMaterial({ color: 0xc9a24a }));
    line.scale.z = 3;
    obj.add(line);
    obj.add(new THREE.Mesh(new THREE.SphereGeometry(0.015, 12, 8), new THREE.MeshBasicMaterial({ color: 0xe8e0cc })));
    const dot = new THREE.Mesh(new THREE.CircleGeometry(0.012, 20), new THREE.MeshBasicMaterial({ color: 0xffe9a8, depthTest: false }));
    dot.renderOrder = 99;
    dot.visible = false;
    scene.add(dot);
    obj.addEventListener('selectstart', function (ev) { tapFrom(obj, ev); });
    obj.addEventListener('squeezestart', function () { placed = 0; });   // a squeeze brings everything back in front of you
    scene.add(obj);
    pointers.push({ obj: obj, line: line, dot: dot });
  }
  layout();
  setMode(false);
}

// Puts the panel, the board and the signs where they belong for a head at height headY.
function layout() {
  full.position.set(0, headY - 0.05, -PANEL_DISTANCE);
  tableGroup.position.set(0, headY - 0.5, -0.85);
  tableGroup.rotation.set(-(Math.PI / 2 - SLOPE), 0, 0);
  hudBar.position.set(0, headY - 0.02, -1.25);
  hudSide.position.set(-1.2, headY - 0.2, -0.88);
  hudSide.rotation.set(0, 0.8, 0);
  hudKeys.position.set(0.6, headY + 0.12, -1.2);
  if (room) room.setBoard(headY, boardSize[0], boardSize[1]);
}

// Where a ray hits a plane that shows (a part of) the panel's canvas, as a point on that canvas.
// The uv a hit reports is already a point of the whole canvas's texture, even on a cropped plane.
function planeHit(r, mesh) {
  const h = r.intersectObject(mesh, false);
  if (!h.length || !h[0].uv) return null;
  const b = window.TCVR;
  return { kind: 'panel', x: h[0].uv.x * b.width, y: (1 - h[0].uv.y) * b.height, dist: h[0].distance, point: h[0].point };
}

// What a ray is pointing at: {kind: 'panel', x, y} or {kind: 'card', slot}, with the distance and point, or null.
function pointAt(r) {
  let best = null;
  function consider(h) { if (h && (!best || h.dist < best.dist)) best = h; }
  if (!tableMode) {
    consider(planeHit(r, full));
  } else {
    consider(planeHit(r, hudBar));
    consider(planeHit(r, hudSide));
    if (hudKeys.visible) consider(planeHit(r, hudKeys));
    const c = board.pick(r);
    if (c) consider({ kind: 'card', slot: c.slot, dist: c.distance, point: c.point });
  }
  return best;
}

function hitOf(obj) {
  tmpMat.identity().extractRotation(obj.matrixWorld);
  raycaster.ray.origin.setFromMatrixPosition(obj.matrixWorld);
  raycaster.ray.direction.set(0, 0, -1).applyMatrix4(tmpMat);
  return pointAt(raycaster);
}

function doTap(hit) {
  if (!hit) return;
  if (hit.kind === 'card') window.TCVR.tapSlot(hit.slot);
  else window.TCVR.tap(hit.x, hit.y);
}

function tapFrom(obj, ev) {
  obj.updateMatrixWorld(true);
  const hit = hitOf(obj);
  if (!hit) return;
  doTap(hit);
  try {                                                  // a short buzz in the controller
    const gp = ev && ev.data && ev.data.gamepad;
    if (gp && gp.hapticActuators && gp.hapticActuators[0]) gp.hapticActuators[0].pulse(0.35, 30);
  } catch (e) { }
}

// Puts everything straight ahead of where you are looking.
function placeRig() {
  const cam = renderer.xr.isPresenting ? renderer.xr.getCamera() : camera;
  cam.updateMatrixWorld(true);
  const pos = new THREE.Vector3().setFromMatrixPosition(cam.matrixWorld);
  const dir = new THREE.Vector3(0, 0, -1).transformDirection(cam.matrixWorld);
  dir.y = 0;
  if (dir.lengthSq() < 1e-4) dir.set(0, 0, -1);
  dir.normalize();
  rig.position.set(pos.x, 0, pos.z);
  rig.rotation.y = Math.atan2(-dir.x, -dir.z);
  headY = pos.y;
  layout();
}

function setMode(table) {
  tableMode = table;
  full.visible = !table;
  tableGroup.visible = table;
  hudBar.visible = hudSide.visible = table;
  if (room) room.podium.visible = table;            // the table would stand in front of the flat panel
  if (!table) hudKeys.visible = false;
}

function updatePointers() {
  let hoverSlot = -1;
  for (const p of pointers) {
    const active = p.obj.visible !== false;
    p.line.visible = active;
    p.dot.visible = false;
    p.line.scale.z = 3;
    if (!active) continue;
    p.obj.updateMatrixWorld(true);
    const hit = hitOf(p.obj);
    if (hit) {
      p.line.scale.z = hit.dist;
      p.dot.position.copy(hit.point);
      p.dot.quaternion.copy(rig.quaternion);
      p.dot.position.addScaledVector(new THREE.Vector3(0, 0, 1).applyQuaternion(p.dot.quaternion), 0.004);
      p.dot.visible = true;
      if (hit.kind === 'card') hoverSlot = hit.slot;
    }
  }
  board.setHover(hoverSlot);
}

// The game's side of one frame: time, the panel's picture, and whether the cards are a 3D table.
function gameFrame(t) {
  const flags = window.TCVR.frame(t);
  if (flags & 1) texture.needsUpdate = true;
  if (flags & 2) { stop(); return false; }
  const wantTable = !!(flags & 4);
  if (wantTable !== tableMode) setMode(wantTable);
  if (tableMode) {
    const snap = window.TCVR.table();
    if (snap) {
      hudKeys.visible = !!snap[12];
      board.update(snap, t);
      const sz = board.size(snap);
      if (Math.abs(sz[0] - boardSize[0]) > 0.005 || Math.abs(sz[1] - boardSize[1]) > 0.005) {
        boardSize[0] = sz[0]; boardSize[1] = sz[1];
        layout();
      }
    }
  }
  if (room) {
    room.setStyle(window.TCVR.style());
    room.update(t);
  }
  return true;
}

function countFrames(t) {
  stats.frames++;
  if (!stats.since) stats.since = t;
  if (t - stats.since >= 1000) {
    const fps = Math.round(stats.frames * 1000 / (t - stats.since));
    const i = renderer.info.render;
    window.TCVR.debug(DEBUG ? 'vr ' + BUILD + '  ' + fps + ' fps  ' + i.calls + ' calls  ' + Math.round(i.triangles / 1000) + 'k tris' : 'vr ' + BUILD);
    stats.frames = 0;
    stats.since = t;
  }
}

export async function startXR(btn) {
  if (!renderer) build();
  say(btn, 'Starting VR...');
  session = await navigator.xr.requestSession('immersive-vr', {
    optionalFeatures: ['local-floor', 'bounded-floor', 'hand-tracking']
  });
  session.addEventListener('end', onSessionEnd);
  await renderer.xr.setSession(session);
  placed = 0;
  setMode(false);
  window.TCVR.enter();
  if (DEBUG) window.TCVR.setCheats(true);              // ?vrdebug: a "+900 coins" button on the menu, for testing
  renderer.setAnimationLoop(function (t) {
    if (!gameFrame(t)) return;
    if (placed < 3) {                                    // wait for a few frames: the head pose is not valid at first
      placed++;
      if (placed === 3) placeRig();
    }
    updatePointers();
    renderer.render(scene, camera);
    countFrames(t);
  });
  say(btn, 'Enter VR');
}

function onSessionEnd() {
  renderer.setAnimationLoop(null);
  session = null;
  window.TCVR.exit();
}

// Leaves VR, in a headset or in the preview window.
function stop() {
  if (session) { session.end(); return; }
  if (previewEl) {
    renderer.setAnimationLoop(null);
    previewEl.remove();
    previewEl = null;
    window.TCVR.exit();
  }
}

// ---- the preview: the same in an ordinary window, the mouse as the pointer ----
export function startPreview() {
  if (!renderer) build();
  renderer.xr.enabled = false;
  const el = renderer.domElement;
  el.style.cssText = 'position:fixed;inset:0;width:100%;height:100%;z-index:50;touch-action:none;background:#0d0814';
  document.body.appendChild(el);
  previewEl = el;
  rig.position.set(0, 0, 0);
  rig.rotation.set(0, 0, 0);
  headY = 1.2;
  layout();
  setMode(false);
  function size() {
    renderer.setSize(window.innerWidth, window.innerHeight, false);
    camera.aspect = window.innerWidth / window.innerHeight;
    camera.updateProjectionMatrix();
  }
  // the camera: far enough back to see the whole panel, or at eye height looking at the board
  function pose() {
    const halfV = Math.tan(THREE.MathUtils.degToRad(camera.fov / 2));
    if (tableMode) {
      camera.position.set(0, headY, 0);
      camera.rotation.order = 'YXZ';
      camera.rotation.set(-0.5 + look.pitch, look.yaw, 0);     // A/D turn, W/S tilt
    } else {
      const need = (PANEL_WIDTH / 2 * 1.04) / (halfV * Math.min(camera.aspect, 99));
      camera.position.set(0, headY - 0.05, -PANEL_DISTANCE + Math.max(need, 0.5));
      camera.lookAt(0, headY - 0.05, -PANEL_DISTANCE);
    }
    camera.updateMatrixWorld(true);
  }
  const look = { yaw: 0, pitch: 0 };
  size();
  window.addEventListener('resize', size);
  window.TCVR.enter();
  if (DEBUG) window.TCVR.setCheats(true);
  const ndc = new THREE.Vector2();
  function aim(ev) {
    const r = el.getBoundingClientRect();
    ndc.set(((ev.clientX - r.left) / r.width) * 2 - 1, -((ev.clientY - r.top) / r.height) * 2 + 1);
    raycaster.setFromCamera(ndc, camera);
    return pointAt(raycaster);
  }
  el.addEventListener('pointerdown', function (ev) { doTap(aim(ev)); });
  el.addEventListener('pointermove', function (ev) {
    const h = tableMode ? aim(ev) : null;
    board.setHover(h && h.kind === 'card' ? h.slot : -1);
  });
  window.addEventListener('keydown', function (ev) {
    if (!previewEl) return;
    if (ev.key === 'Escape') stop();
    else if (ev.key === 'a') look.yaw += 0.12;
    else if (ev.key === 'd') look.yaw -= 0.12;
    else if (ev.key === 'w') look.pitch += 0.1;
    else if (ev.key === 's') look.pitch -= 0.1;
  });
  renderer.setAnimationLoop(function (t) {
    if (!gameFrame(t)) return;
    pose();
    renderer.render(scene, camera);
    countFrames(t);
  });
}

