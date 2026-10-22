// The 3D Wrangler: loads the model, paints it, and exposes everything the app can do to it.
// Every change animates (doors swing, hood lifts, camera glides); nothing pops.
import * as THREE from 'three'
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js'
import { RoomEnvironment } from 'three/addons/environments/RoomEnvironment.js'
import { OrbitControls } from 'three/addons/controls/OrbitControls.js'
import { MeshoptDecoder } from 'three/addons/libs/meshopt_decoder.module.js'

const ease = (t) => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2)
const DOORS = { BL: 'Door', BR: 'Door_2', FL: 'Door_3', FR: 'Door_4' }

export async function createJeep(canvas, { url, onProgress, onFrame } = {}) {
  const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: true })
  renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2))
  renderer.toneMapping = THREE.ACESFilmicToneMapping
  renderer.shadowMap.enabled = true
  renderer.shadowMap.type = THREE.PCFSoftShadowMap

  const scene = new THREE.Scene()
  const pmrem = new THREE.PMREMGenerator(renderer)
  const envDay = pmrem.fromScene(new RoomEnvironment(), 0.02).texture
  scene.environment = envDay

  const cam = new THREE.PerspectiveCamera(24, 1, 0.1, 100)
  const controls = new OrbitControls(cam, canvas)
  controls.enableDamping = true; controls.dampingFactor = 0.08
  controls.enablePan = false; controls.enableZoom = false
  controls.minPolarAngle = 0.05; controls.maxPolarAngle = Math.PI * 0.47
  controls.rotateSpeed = 0.6
  controls.target.set(0, 0.9, 0)

  // ---------- model ----------
  const loader = new GLTFLoader(); loader.setMeshoptDecoder(MeshoptDecoder)
  const gltf = await loader.loadAsync(url, (e) => onProgress?.(e.total ? e.loaded / e.total : 0))
  const car = gltf.scene
  const mats = {}
  car.traverse((o) => {
    if (!o.isMesh) return
    o.castShadow = true; o.receiveShadow = true
    for (const m of [].concat(o.material)) mats[m.name] ||= m
  })
  // gloss black paint, black leather, 20% tinted glass
  const paint = mats.JMI_1355060001_004
  paint.color.setRGB(0.012, 0.013, 0.015); paint.metalness = 0.55; paint.roughness = 0.2
  for (const n of ['JMI_Cabin_Leather_A1', 'JMI_Cabin_Leather_B1', 'JMI_Cabin_Leather_C1']) {
    const m = mats[n]; if (!m) continue
    m.map = null; m.color.setRGB(0.035, 0.035, 0.038); m.roughness = 0.55; m.needsUpdate = true
  }
  // matte black rims (Method 305 NV)
  for (const n of Object.keys(mats)) if (/Rim/i.test(n)) { const m = mats[n]; m.map = null; m.color.setRGB(0.025, 0.025, 0.027); m.metalness = 0.25; m.roughness = 0.85; m.needsUpdate = true }
  const glass = mats.Glass
  glass.color.setRGB(0.02, 0.022, 0.026); glass.transmission = 0.2; glass.roughness = 0.04; glass.metalness = 0.1; glass.needsUpdate = true
  const head = mats.JMI_Light_010, tail = mats.red_glass, amber = mats.orange_glass
  head.emissive = new THREE.Color(1, 1, 1); head.emissiveIntensity = 0
  tail.emissive = new THREE.Color(1, 0, 0); tail.emissiveIntensity = 0
  amber.emissive = new THREE.Color(1, 0.45, 0); amber.emissiveIntensity = 0

  // centre on the ground, ~4.8 m long
  const box = new THREE.Box3().setFromObject(car); const size = box.getSize(new THREE.Vector3()); const c = box.getCenter(new THREE.Vector3())
  const s = 4.8 / Math.max(size.x, size.z)
  car.scale.setScalar(s); car.position.set(-c.x * s, -box.min.y * s, -c.z * s)
  const root = new THREE.Group(); root.add(car); scene.add(root)
  root.updateMatrixWorld(true)
  const byName = (n) => root.getObjectByName(n)   // search from root: hinged parts move out from under 'car'
  const local = (o) => { root.updateMatrixWorld(true); const b = new THREE.Box3().setFromObject(o); return { min: root.worldToLocal(b.min.clone()), max: root.worldToLocal(b.max.clone()), c: root.worldToLocal(b.getCenter(new THREE.Vector3())) } }
  const front = Math.sign(local(byName(DOORS.FL)).c.z - local(byName(DOORS.BL)).c.z) || 1   // +1: front is +z (front doors sit ahead of rear doors)

  // put a group on a hinge (pivot) so it can swing
  function hingeAt(objs, p) {
    const h = new THREE.Object3D(); h.position.copy(p); root.add(h); h.updateMatrixWorld(true)
    for (const o of objs) h.attach(o)
    return h
  }
  // doors: hinge on the front edge, outer side; swing outwards
  const doors = {}
  for (const [k, n] of Object.entries(DOORS)) {
    const g = byName(n); const b = local(g)
    const outerX = Math.abs(b.min.x) > Math.abs(b.max.x) ? b.min.x : b.max.x
    const h = hingeAt([g], new THREE.Vector3(outerX, 0, front > 0 ? b.max.z : b.min.z))
    h.rotation.y = 0.5; const a = Math.abs(local(g).c.x); h.rotation.y = -0.5; const bb = Math.abs(local(g).c.x); h.rotation.y = 0
    doors[k] = { hinge: h, sign: a > bb ? 1 : -1, open: 0, glass: [] }
    g.traverse((o) => { if (o.isMesh && [].concat(o.material).some((m) => m === glass)) doors[k].glass.push(o) })
  }
  // hood and tailgate live together in "group2"; split them by mesh name
  const g2 = byName('group2'); const hoodParts = [], gateParts = []
  g2.traverse((o) => { if (o.isMesh) { const n = o.name + (o.parent?.name || ''); if (/Hood/.test(n)) hoodParts.push(o); else if (/Trunk/.test(n)) gateParts.push(o) } })
  for (const t of [...byName('Jgroup1').children]) if (/Trunk/.test(t.name)) gateParts.push(t)
  const hoodBox = new THREE.Box3(); for (const o of hoodParts) hoodBox.union(new THREE.Box3().setFromObject(o))
  const hMin = root.worldToLocal(hoodBox.min.clone()), hMax = root.worldToLocal(hoodBox.max.clone())
  const hood = { hinge: hingeAt(hoodParts, new THREE.Vector3(0, hMax.y, front > 0 ? hMin.z : hMax.z)), open: 0 }
  const gateBox = new THREE.Box3(); for (const o of gateParts) gateBox.union(new THREE.Box3().setFromObject(o))
  const gMin = root.worldToLocal(gateBox.min.clone()), gMax = root.worldToLocal(gateBox.max.clone())
  // a Wrangler's swing gate hinges on the passenger side (car's right)
  const rightX = front > 0 ? gMin.x : gMax.x
  const gate = { hinge: hingeAt(gateParts, new THREE.Vector3(rightX, 0, front > 0 ? gMin.z : gMax.z)), open: 0 }

  const panels = byName('group1'), hardtop = byName('roof')
  // fixed points on the body (closed position) so the UI can pin labels and tap targets to parts
  const anchors = {}
  for (const [k, n] of Object.entries(DOORS)) { const b = local(byName(n)); anchors[k] = new THREE.Vector3(b.c.x * 1.15, b.max.y * 0.8, b.c.z) }
  anchors.hood = new THREE.Vector3(0, hMax.y, (hMin.z + hMax.z) / 2)
  anchors.gate = new THREE.Vector3(0, (gMin.y + gMax.y) / 2, front > 0 ? gMin.z : gMax.z)
  { const b = local(hardtop); anchors.roof = new THREE.Vector3(0, b.max.y, b.c.z) }
  const sx = front > 0 ? 1 : -1   // driver's side is +x when the front is +z
  anchors.seatFL = new THREE.Vector3(0.38 * sx, 1.05, front * 0.2); anchors.seatFR = new THREE.Vector3(-0.38 * sx, 1.05, front * 0.2)
  anchors.seatBL = new THREE.Vector3(0.48 * sx, 1.05, front * -0.62); anchors.seatBM = new THREE.Vector3(0, 1.05, front * -0.62); anchors.seatBR = new THREE.Vector3(-0.48 * sx, 1.05, front * -0.62)
  anchors.wheel = new THREE.Vector3(0.4 * sx, 1.15, front * 0.74)
  // the steering (front) wheels: the model's wheel nodes are named for the other end, so pick by position
  const wheelNodes = ['FL', 'FR', 'BL', 'BR'].map(byName).filter(Boolean).sort((a, b) => (local(b).c.z - local(a).c.z) * front)
  const wheels = { FL: wheelNodes[0], FR: wheelNodes[1] }
  const wheelPivots = {}
  for (const [k, w] of Object.entries(wheels)) { const b = local(w); wheelPivots[k] = hingeAt([w], b.c) }

  // ---------- light ----------
  const key = new THREE.DirectionalLight(0xffffff, 2.0); key.position.set(3, 10, 4); key.castShadow = true
  key.shadow.mapSize.set(2048, 2048); Object.assign(key.shadow.camera, { left: -6, right: 6, top: 6, bottom: -6 }); key.shadow.radius = 8; key.shadow.bias = -0.0004
  const rim = new THREE.DirectionalLight(0xdfe8ff, 1.3); rim.position.set(-6, 4, -5)
  const fill = new THREE.DirectionalLight(0xffffff, 0.5); fill.position.set(6, 2, -2)
  scene.add(key, rim, fill)
  const floor = new THREE.Mesh(new THREE.PlaneGeometry(60, 60), new THREE.ShadowMaterial({ opacity: 0.55 }))
  floor.rotation.x = -Math.PI / 2; floor.receiveShadow = true; scene.add(floor)
  // headlight beams: two spotlights onto the ground ahead
  const beams = []
  const fb = local(car)
  for (const x of [-0.65, 0.65]) {
    const sp = new THREE.SpotLight(0xf3f6ff, 0, 14, 0.42, 0.6, 1.2)
    sp.position.set(x, 1.05, front > 0 ? fb.max.z - 0.1 : fb.min.z + 0.1)
    sp.target.position.set(x * 1.6, 0, sp.position.z + front * 8)
    root.add(sp, sp.target); beams.push(sp)
  }
  // at night the beams land on a faint pool of light on the ground: two soft additive gradients ahead of the headlights
  const poolTex = (() => { const c = document.createElement('canvas'); c.width = c.height = 256; const g = c.getContext('2d'); const r = g.createRadialGradient(128, 128, 0, 128, 128, 128); r.addColorStop(0, 'rgba(255,255,255,1)'); r.addColorStop(0.35, 'rgba(255,255,255,.45)'); r.addColorStop(1, 'rgba(255,255,255,0)'); g.fillStyle = r; g.fillRect(0, 0, 256, 256); const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; return t })()
  const pools = []
  for (const x of [-0.75, 0.75]) {
    const m = new THREE.Mesh(new THREE.PlaneGeometry(2.4, 3.0), new THREE.MeshBasicMaterial({ map: poolTex, color: 0xd9e2ff, transparent: true, opacity: 0, depthWrite: false, blending: THREE.CustomBlending, blendSrc: THREE.SrcAlphaFactor, blendDst: THREE.OneFactor, blendSrcAlpha: THREE.ZeroFactor, blendDstAlpha: THREE.OneFactor }))  // add light to the page without touching the canvas alpha
    m.rotation.x = -Math.PI / 2; m.position.set(x * 1.3, 0.004, (front > 0 ? fb.max.z : fb.min.z) + front * 1.15); m.renderOrder = -1
    root.add(m); pools.push(m)
  }

  // ---------- state + animation ----------
  const state = { lights: 0, brake: 0, signal: false, night: false }
  const tweens = []
  function tween(get, set, to, ms = 650, tag) { if (window.__jeepInstant) ms = 1; if (tag) for (let i = tweens.length - 1; i >= 0; i--) if (tweens[i].tag === tag) tweens.splice(i, 1); const from = get(); const t0 = performance.now(); tweens.push({ from, to, t0, ms, set, tag }); kick() }
  function setDoor(k, open) { const d = doors[k]; tween(() => d.open, (v) => { d.open = v; d.hinge.rotation.y = d.sign * v * THREE.MathUtils.degToRad(64) }, open ? 1 : 0, 800) }
  function setHood(open) { tween(() => hood.open, (v) => { hood.open = v; hood.hinge.rotation.x = -front * v * THREE.MathUtils.degToRad(48) }, open ? 1 : 0, 900) }
  function setGate(open) { tween(() => gate.open, (v) => { gate.open = v; gate.hinge.rotation.y = -front * Math.sign(rightX) * v * THREE.MathUtils.degToRad(80) }, open ? 1 : 0, 900) }
  function setLights(on) { tween(() => state.lights, (v) => { state.lights = v; head.emissiveIntensity = v * 3.2; for (const b of beams) b.intensity = v * (state.night ? 60 : 18); for (const p of pools) p.material.opacity = v * (state.night ? 0.24 : 0); tail.emissiveIntensity = Math.max(v * 0.8, state.brake * 2.4) }, on ? 1 : 0, 350) }
  function setBrake(on) { tween(() => state.brake, (v) => { state.brake = v; tail.emissiveIntensity = Math.max(state.lights * 0.8, v * 2.4) }, on ? 1 : 0, 150) }
  let roofMode = 'on', peek = false
  function applyRoof() { panels.visible = !peek && roofMode === 'on'; hardtop.visible = !peek && roofMode !== 'off'; kick() }
  function setRoof(mode) { roofMode = mode; applyRoof() } // 'on' | 'panels' | 'off'
  function setPeek(on) { peek = on; applyRoof() }        // look inside (climate screen) without changing the real roof
  function setWindows(down) { for (const d of Object.values(doors)) for (const g of d.glass) g.visible = !down; kick() }
  function setDoorsOff(off) { for (const n of Object.values(DOORS)) byName(n).visible = !off; kick() }
  function steer(deg) { const r = THREE.MathUtils.degToRad(deg); for (const p of Object.values(wheelPivots)) tween(() => p.rotation.y, (v) => { p.rotation.y = v }, r, 600) }
  function setSignal(on) { state.signal = on; if (!on) amber.emissiveIntensity = 0; kick() }
  function setNight(on) {
    state.night = on
    scene.environmentIntensity = on ? 0.32 : 1
    key.intensity = on ? 0.5 : 2; rim.intensity = on ? 0.9 : 1.3; fill.intensity = on ? 0.15 : 0.5
    renderer.toneMappingExposure = on ? 1.15 : 1
    setLights(state.lights > 0.5)
    kick()
  }

  // camera presets, glide between them
  const VIEWS = {
    hero: { az: 38, el: 25, d: 12.5, y: 0.9 },
    side: { az: 90, el: 10, d: 11.5, y: 0.95 },
    front: { az: 15, el: 12, d: 11, y: 0.95 },
    rear: { az: -140, el: 16, d: 11.5, y: 0.95 },
    top: { az: 180, el: 89, d: 11.4, y: 0 },
  }
  // narrow (portrait) canvases: back the camera off so the whole Jeep stays in frame with air around it
  const fit = (v) => { const a = canvas.clientWidth / Math.max(1, canvas.clientHeight); return v.el > 80 || a >= 1 ? 1 : Math.min(2.4, 0.96 / a) }
  const sph = (v) => { const az = THREE.MathUtils.degToRad(v.az), el = THREE.MathUtils.degToRad(v.el), d = v.d * fit(v); return new THREE.Vector3(Math.cos(el) * Math.sin(az) * d, Math.sin(el) * d + v.y, Math.cos(el) * Math.cos(az) * d) }
  let view = 'hero'
  function setView(name, ms = 900) {
    view = name
    let v = VIEWS[name]
    // top view: the Jeep's long axis follows the screen's long axis (front up on portrait, front right on landscape)
    if (name === 'top') {
      const a = canvas.clientWidth / Math.max(1, canvas.clientHeight), t = Math.tan(THREE.MathUtils.degToRad(12))
      // the roof sits ~1.7 m closer to the camera than the ground, so frame it, not the ground
      v = a < 1.25 ? { ...v, az: 180, d: Math.max(13.5, 2.7 / (2 * t * a) + 1.7) } : { ...v, az: -90, d: Math.max(5.8 / (2 * t * a) + 1.7, 7) }
    }
    const fromP = cam.position.clone(), toP = sph(v); const fromT = controls.target.clone(), toT = new THREE.Vector3(0, v.y, 0)
    tween(() => 0, (k) => { cam.position.lerpVectors(fromP, toP, k); controls.target.lerpVectors(fromT, toT, k) }, 1, ms, 'cam')
  }
  cam.position.copy(sph(VIEWS.hero))
  // where a part sits on screen, in CSS pixels of the canvas (for labels and tap targets)
  const _p = new THREE.Vector3()
  function anchor(name) {
    const a = anchors[name]; if (!a) return null
    _p.copy(a).project(cam)
    return { x: (_p.x + 1) / 2 * canvas.clientWidth, y: (1 - _p.y) / 2 * canvas.clientHeight, visible: _p.z < 1 }
  }

  // ---------- a tiny second view of the same car (for the map marker) ----------
  // Shares geometry and materials with the main model; its own small renderer. Call .destroy() when done.
  function miniView(canvas2) {
    const r2 = new THREE.WebGLRenderer({ canvas: canvas2, antialias: true, alpha: true })
    r2.setPixelRatio(Math.min(window.devicePixelRatio, 3)); r2.toneMapping = THREE.ACESFilmicToneMapping; r2.toneMappingExposure = 1.7
    const s2 = new THREE.Scene(); s2.environment = new THREE.PMREMGenerator(r2).fromScene(new RoomEnvironment(), 0.02).texture
    const clone = root.clone(true); s2.add(clone)
    const extras = []; clone.traverse((o) => { if (o.isLight || o === clone.getObjectByProperty('isSpotLightTarget', true)) extras.push(o) }); for (const o of extras) o.removeFromParent()
    const k2 = new THREE.DirectionalLight(0xffffff, 2.6); k2.position.set(3, 8, 5); s2.add(k2)
    s2.add(new THREE.HemisphereLight(0xffffff, 0x444444, 1.2)); const rim2 = new THREE.DirectionalLight(0xdfe8ff, 1.6); rim2.position.set(-5, 6, -6); s2.add(rim2)
    const c2 = new THREE.PerspectiveCamera(22, 1, 0.1, 100)
    const wheelNodes2 = ['FL', 'FR', 'BL', 'BR'].map((n) => clone.getObjectByName(n)).filter(Boolean)
    let raf2 = 0, spinning = false, last = 0
    function size() { const w = canvas2.clientWidth, h = canvas2.clientHeight; if (!w || !h) return; r2.setSize(w, h, false); c2.aspect = w / h; c2.updateProjectionMatrix() }
    // Uber-style: seen from above at ~58°, the car turned to its heading (0 = north/up, clockwise)
    let heading = 0
    function place() {
      const el = THREE.MathUtils.degToRad(58), d = 15
      c2.fov = 26; c2.position.set(0, Math.sin(el) * d, Math.cos(el) * d); c2.lookAt(0, 0.6, 0); c2.updateProjectionMatrix()
      clone.rotation.y = -THREE.MathUtils.degToRad(heading) + (front > 0 ? Math.PI : 0)
    }
    function draw(t) {
      raf2 = 0
      if (spinning) { const dt = last ? Math.min(0.05, (t - last) / 1000) : 0; last = t; for (const w of wheelNodes2) w.rotation.x += dt * 4.5 * front; raf2 = requestAnimationFrame(draw) }
      r2.render(s2, c2)
    }
    const ro = new ResizeObserver(() => { size(); place(); if (!raf2) raf2 = requestAnimationFrame(draw) }); ro.observe(canvas2)
    size(); place(); raf2 = requestAnimationFrame(draw)
    return {
      spin(on) { spinning = on; last = 0; if (on && !raf2) raf2 = requestAnimationFrame(draw) },
      heading(deg) { heading = deg; place(); if (!raf2) raf2 = requestAnimationFrame(draw) },
      destroy() { spinning = false; cancelAnimationFrame(raf2); ro.disconnect(); s2.environment.dispose(); r2.dispose(); r2.forceContextLoss?.() },
    }
  }

  // ---------- render loop (only while something is moving) ----------
  let raf = 0, lastAspect = 0
  function frame(t) {
    raf = 0
    let busy = false
    for (let i = tweens.length - 1; i >= 0; i--) {
      const w = tweens[i]; const k = Math.min(1, (t - w.t0) / w.ms)
      w.set(w.from + (w.to - w.from) * ease(k)); if (k < 1) busy = true; else tweens.splice(i, 1)
    }
    if (state.signal) { amber.emissiveIntensity = Math.floor(t / 420) % 2 ? 2.5 : 0; busy = true }
    busy = controls.update() || busy
    renderer.render(scene, cam)
    onFrame?.()
    if (busy) kick()
  }
  function kick() { if (!raf) raf = requestAnimationFrame(frame) }
  controls.addEventListener('change', kick)
  controls.addEventListener('start', kick)

  function resize() {
    const w = canvas.clientWidth, h = canvas.clientHeight
    if (!w || !h) return
    renderer.setSize(w, h, false); cam.aspect = w / h
    // keep the whole Jeep in frame on tall phones and wide desktops alike
    cam.fov = 24
    cam.updateProjectionMatrix()
    const a = w / h; if (view && lastAspect && Math.abs(a - lastAspect) > 0.08) setView(view, 400); else if (view && !lastAspect) setView(view, 1); lastAspect = a
    kick()
  }
  new ResizeObserver(resize).observe(canvas); resize()

  return { setDoor, setHood, setGate, setLights, setBrake, setRoof, setWindows, setDoorsOff, steer, setSignal, setNight, setView, setPeek, anchor, miniView, doors, front, kick, renderer, cam }
}
