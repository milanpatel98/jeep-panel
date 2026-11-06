// The 3D Jeep for the CarPlay screen (loaded full-screen in a web view). Black Jeep on a faint
// mirror floor that fades out to nothing; the page itself is transparent. It opens with Milan's
// Jeep loading screen, then from above makes one slow turn to the three-quarter view.
// Over the canvas: Tesla-style call-outs (a lock above the roof, "Door / Open" hairlines, the
// charge port), the roof strip (a dotted track with the Jeep's top view as the thumb) and, in
// the tires view, the four pressures. The page takes no touches: the app drives it with
// window.jeepEmbed — apply(state), spin(deg) / release(), strip(dy, step) / stripRelease(),
// zoom(scale) / zoomEnd(), layout(region) / layoutRelease().
import * as THREE from 'three'
import { Reflector } from 'three/addons/objects/Reflector.js'
import { createJeep } from './jeep.js'
import { jeepLoader } from './loader.js'
import {
  embedCalls, overlayCalls, shortestTurn, fitBox, boxCorners,
  stripIndex, stripThumbY, STRIP_PITCH, STRIP_STEPS, carBox, SLIDE, SLIDE_MS, calloutLayout,
} from './embedState.js'

const canvas = document.getElementById('c')
const ui = document.getElementById('ui')
const linesSvg = document.getElementById('lines')
const stripEl = document.getElementById('strip')
const params = new URLSearchParams(location.search)
const post = (msg) => window.webkit?.messageHandlers?.jeep?.postMessage(msg)
const SVG = 'http://www.w3.org/2000/svg'

const DEFAULTS = { theme: 'dark', lights: false, roof: 'on', doorsOff: false, doors: { FL: false, FR: false, BL: false, BR: false }, gate: false, mode: 'hero' }
let shown = structuredClone(DEFAULTS)   // what the 3D Jeep and the overlay show now
let wanted = {}                         // everything the app has asked for so far
let jeep = null
let reducedMotion = !!window.matchMedia?.('(prefers-reduced-motion: reduce)').matches
let settle = 0, settled = false

const merge = (a, b) => ({ ...a, ...b, ...(b.doors ? { doors: { ...a.doors, ...b.doors } } : {}) })

// the loading screen: Milan's Jeep rolls in, its wheels turn while the model loads
const loader = jeepLoader(document.body, { base: new URL('./', document.baseURI).href })
loader.still(reducedMotion)
requestAnimationFrame(() => post({ type: 'loader' }))

let heroAt = 0   // when the opening turn lands: the call-outs appear then
function toHero() {
  clearTimeout(settle)
  if (settled || !jeep) return
  settled = true
  const ms = reducedMotion ? 1 : 1600
  heroAt = performance.now() + ms
  setTimeout(placeOverlay, ms + 20)
  if (mode === 'hero') jeep.setView('hero', ms)
}

// ---------- the overlay's own state ----------
let mode = 'hero'                      // 'hero' | 'turntable' | 'tires'
let lock = null                        // true locked, false unlocked, null unknown
let charge = null                      // 'Charging · full by 6:10 PM', 'Plugged in', or null
let tires = null                       // { FL, FR, RL, RR, ago }
let region = null                      // where the car lives, px of the canvas: { x0, y0, x1, y1 }
let regionWanted = null                // the last region the app applied (a drag can pull away from it)

const page = {
  setMode(m) { setMode(m) },
  setLock(v) { lock = v; placeOverlay() },
  setCharge(v) { charge = v; placeOverlay() },
  setTires(v) { tires = v; placeOverlay() },
  setRegion(r) { regionWanted = r; setRegion(r, SLIDE_MS) },
}

function sync() {
  const theme = wanted.theme === 'light' ? 'light' : 'dark'
  document.documentElement.dataset.theme = theme
  for (const [method, ...args] of overlayCalls(shown, wanted)) page[method](...args)
  if (!jeep) return   // the 3D calls wait for the model (the overlay calls run again then: harmless)
  for (const [method, ...args] of embedCalls(shown, wanted)) jeep[method](...args)
  shown = merge(shown, wanted)
  placeStrip()
}

// ---------- spin: a horizontal drag turns the Jeep on its vertical axis, 1:1 ----------
// After 2.5 s with no drag it glides back to the 3/4 view (900 ms ease-in-out), like the phone.
const ease = (t) => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2)
let yaw = 0, glideRaf = 0, idle = 0
let floor = null   // the mirror floor's uniforms: its fade follows the Jeep's footprint as it turns
function setYaw(deg) {
  yaw = deg
  if (!jeep) return
  jeep.root.rotation.y = THREE.MathUtils.degToRad(deg)
  if (floor) floor.yaw.value = jeep.root.rotation.y
  jeep.kick()
}
function stopGlide() { cancelAnimationFrame(glideRaf); glideRaf = 0; clearTimeout(idle) }
// While a drag turns the Jeep the camera stands back to the fit for every angle (it never clips);
// back at the 3/4 view it closes in again to the big fit for that one angle.
let spinFit = false
function setSpinFit(on, ms) {
  if (spinFit === on) return
  spinFit = on
  if (jeep && settled) frameView(reducedMotion ? 1 : ms)
}
function glideHome(then) {
  stopGlide()
  const from = shortestTurn(yaw)
  if (reducedMotion || Math.abs(from) < 0.05) { setYaw(0); setSpinFit(false, 500); then?.(); return }
  const t0 = performance.now()
  const step = (t) => {
    const k = Math.min(1, (t - t0) / 900)
    setYaw(from * (1 - ease(k)))
    glideRaf = k < 1 ? requestAnimationFrame(step) : 0
    if (k >= 1) { setSpinFit(false, 500); then?.() }
  }
  glideRaf = requestAnimationFrame(step)
}

// ---------- the turntable: the top view turning on its own, once in 24 s ----------
let turnRaf = 0, turnLast = 0
function turntable(on) {
  cancelAnimationFrame(turnRaf); turnRaf = 0; turnLast = 0
  if (!on || reducedMotion) return
  const step = (t) => {
    if (turnLast) setYaw(yaw + ((t - turnLast) / 1000) * (360 / 24))
    turnLast = t
    turnRaf = requestAnimationFrame(step)
  }
  turnRaf = requestAnimationFrame(step)
}

// ---------- zoom: two fingers (iOS 26 cars) scale the camera's view, 1 … 1.8× ----------
let zoomK = 1, zoomRaf = 0, zoomIdle = 0
function setZoom(k) {
  zoomK = Math.min(1.8, Math.max(1, k))
  if (!jeep) return
  jeep.cam.zoom = zoomK
  jeep.cam.updateProjectionMatrix()
  jeep.kick()
  placeOverlay()
}
function zoomHome() {
  cancelAnimationFrame(zoomRaf); clearTimeout(zoomIdle)
  const from = zoomK
  if (reducedMotion || Math.abs(from - 1) < 0.005) { setZoom(1); return }
  const t0 = performance.now()
  const step = (t) => { const k = Math.min(1, (t - t0) / 700); setZoom(1 + (from - 1) * (1 - ease(k))); zoomRaf = k < 1 ? requestAnimationFrame(step) : 0 }
  zoomRaf = requestAnimationFrame(step)
}

// ---------- the views: hero, turntable, tires ----------
function setMode(m) {
  if (mode === m) return
  const was = mode
  mode = m
  if (!jeep) return
  if (m === 'hero') {
    turntable(false)
    settled = true
    glideHome()
    frameView(900, 'hero')
  } else if (m === 'turntable') {
    settled = true
    frameView(900, 'top')
    turntable(true)
  } else {
    turntable(false)
    settled = true
    glideHome()
    frameView(900, 'top')
  }
  jeep.setLift?.(m === 'hero' ? 0 : 1)
  if (was === 'tires' || m === 'tires') placeStrip()
  placeOverlay()
}

// ---------- the region: where the car lives on the page (the map takes the rest) ----------
let regionRaf = 0
function fullRegion() { return { x0: 0, y0: 0, x1: canvas.clientWidth, y1: canvas.clientHeight } }
const sameRegion = (a, b) => !!a && !!b && ['x0', 'y0', 'x1', 'y1'].every((k) => Math.abs(a[k] - b[k]) < 0.5)
function setRegion(r, ms) {
  if (sameRegion(region, r) && !regionRaf) return
  cancelAnimationFrame(regionRaf); regionRaf = 0
  const to = { ...r }
  if (!region || !ms || reducedMotion) { region = to; frameCam(); placeStrip(); return }
  const from = { ...region }, t0 = performance.now()
  const step = (t) => {
    const k = SLIDE(Math.min(1, (t - t0) / ms))
    region = { x0: from.x0 + (to.x0 - from.x0) * k, y0: from.y0 + (to.y0 - from.y0) * k, x1: from.x1 + (to.x1 - from.x1) * k, y1: from.y1 + (to.y1 - from.y1) * k }
    frameCam(); placeStrip()
    regionRaf = k < 1 ? requestAnimationFrame(step) : 0
  }
  regionRaf = requestAnimationFrame(step)
}

// ---------- the roof strip: the thumb follows the finger, then snaps to its step ----------
let stripResidual = 0, stripStep = null   // while a drag is on: the finger's pull and the step the app is at
function stripGeometry() {
  if (!region) return null
  const h = region.y1 - region.y0
  const span = (STRIP_STEPS.length - 1) * STRIP_PITCH
  const top = region.y0 + (h - span) / 2
  return { x: region.x1 - 24, top, span }
}
function placeStrip() {
  const g = stripGeometry()
  const show = !!g && mode !== 'tires' && !!jeep
  stripEl.classList.toggle('hide', !show)
  if (!g) return
  const index = stripStep ?? stripIndex(shown.roof, shown.doorsOff)
  stripEl.style.left = `${g.x - 24}px`
  stripEl.style.top = `${g.top - 70}px`
  stripEl.style.height = `${g.span + 140}px`
  const dots = stripEl.querySelector('.dots')
  dots.style.top = '34px'; dots.style.height = `${g.span + 72}px`
  stripEl.querySelector('.arr.up').style.top = '14px'
  stripEl.querySelector('.arr.dn').style.top = `${g.span + 140 - 24}px`
  const thumb = stripEl.querySelector('.thumb')
  thumb.style.top = `${stripThumbY(index, stripResidual, { top: 70, pitch: STRIP_PITCH })}px`
  const icon = { on: 'roof-on', panels: 'roof-panels', off: 'roof-off', doorsOff: 'roof-doors' }[STRIP_STEPS[index]]
  const img = thumb.querySelector('img')
  const src = new URL(`strip/${icon}.png`, document.baseURI).href
  if (img.getAttribute('src') !== src) img.setAttribute('src', src)
}

// ---------- call-outs and tire labels, pinned to the 3D anchors ----------
const co = {}   // name → element
function el(name, cls, html) {
  if (co[name]) return co[name]
  const d = document.createElement('div'); d.className = cls; d.innerHTML = html; ui.append(d); co[name] = d
  return d
}
const LOCK_SVG = (open) => open
  ? '<svg viewBox="0 0 16 16" fill="currentColor"><path d="M8 1.5a3.5 3.5 0 0 0-3.5 3.5V6h1.5V5a2 2 0 1 1 4 0v.3h1.5V5A3.5 3.5 0 0 0 8 1.5zM4 6.5h8a1 1 0 0 1 1 1v6a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1v-6a1 1 0 0 1 1-1z"/></svg>'
  : '<svg viewBox="0 0 16 16" fill="currentColor"><path d="M8 1.5A3.5 3.5 0 0 0 4.5 5v1.5H4a1 1 0 0 0-1 1v6a1 1 0 0 0 1 1h8a1 1 0 0 0 1-1v-6a1 1 0 0 0-1-1h-.5V5A3.5 3.5 0 0 0 8 1.5zM6 5a2 2 0 1 1 4 0v1.5H6V5z"/></svg>'
const BOLT_SVG = '<svg viewBox="0 0 16 16" fill="currentColor"><path d="M9.2 1 3 9h3.6L6 15l6.6-8.3H9z"/></svg>'

function line(pts) {
  const l = document.createElementNS(SVG, 'line')
  l.setAttribute('x1', pts[0][0]); l.setAttribute('y1', pts[0][1]); l.setAttribute('x2', pts[1][0]); l.setAttribute('y2', pts[1][1])
  linesSvg.append(l)
}
function place(d, x, y, align, show) {
  d.classList.toggle('hide', !show)
  d.classList.toggle('left', align === 'right'); d.classList.toggle('right', align === 'left')
  d.style.left = align === 'right' ? '' : `${x}px`
  d.style.right = align === 'right' ? `${canvas.clientWidth - x}px` : ''
  d.style.top = `${y}px`
}

function placeOverlay() {
  if (!jeep) return
  linesSvg.replaceChildren()
  const anchor = (n) => jeep.anchor(n)
  const centreX = region ? (carBox(region, { strip: mode !== 'tires' }).x0 + carBox(region, { strip: mode !== 'tires' }).x1) / 2 : canvas.clientWidth / 2
  const callouts = mode === 'hero' && settled && performance.now() >= heroAt

  // the lock, above the roof
  const lockEl = el('lock', 'co lock', LOCK_SVG(false))
  const roof = anchor('roof')
  if (callouts && lock !== null && roof?.visible) {
    const c = calloutLayout({ x: roof.x, y: roof.y - 6 }, { rise: 40 })
    line(c.line)
    if (lockEl.dataset.open !== String(lock === false)) { lockEl.dataset.open = String(lock === false); lockEl.classList.toggle('open', lock === false); lockEl.innerHTML = LOCK_SVG(lock === false) }
    lockEl.style.left = `${roof.x - 8}px`; lockEl.style.right = ''; lockEl.style.top = `${c.line[1][1] - 20}px`
    lockEl.classList.remove('hide', 'left', 'right')
  } else lockEl.classList.add('hide')

  // open doors and the tailgate: the label clears the roof (a far-side door's would land on the
  // body otherwise), and labels never sit on each other
  const parts = [['FL', 'Door'], ['FR', 'Door'], ['BL', 'Door'], ['BR', 'Door'], ['gate', 'Tailgate']]
  const labels = []
  for (const [k, name] of parts) {
    const open = k === 'gate' ? shown.gate : shown.doors?.[k]
    const d = el(k, 'co part', `<small>${name}</small><b>Open</b>`)
    const a = open && callouts ? anchor(k) : null
    if (!a || !a.visible) { d.classList.add('hide'); continue }
    const left = a.x < centreX
    const rise = roof?.visible ? Math.max(44, a.y - (roof.y - 18)) : 44
    labels.push({ d, a, left, rise })
  }
  labels.sort((p, q) => p.a.x - q.a.x)
  for (let i = 0; i < labels.length; i++) {
    const l = labels[i]
    for (let j = 0; j < i; j++) {
      const o = labels[j]
      if (Math.abs(o.a.x - l.a.x) < 80 && Math.abs((o.a.y - o.rise) - (l.a.y - l.rise)) < 30) l.rise = l.a.y - (o.a.y - o.rise) + 30
    }
    const c = calloutLayout(l.a, { left: l.left, rise: l.rise })
    line(c.line)
    place(l.d, c.label.x, c.label.y - 2, c.label.align, true)
  }

  // the charge port: a bolt at the port and what's happening
  const ch = el('charge', 'co charge', '')
  const port = charge && callouts ? anchor('charge') : null
  if (port?.visible) {
    // a hairline up from the port (it clears the hood on the far side too), the bolt and the
    // words beside its top, on the outer side
    const left = port.x < centreX
    const c = calloutLayout(port, { left, rise: 40 })
    line(c.line)
    const [head, ...rest] = String(charge).split(' · ')
    const html = `${BOLT_SVG}<b>${head}</b>${rest.length ? `<small>${rest.join(' · ')}</small>` : ''}`
    if (ch.innerHTML !== html) ch.innerHTML = html
    place(ch, c.label.x, c.label.y - 2, c.label.align, true)
  } else ch.classList.add('hide')

  // tires: four pressures at the wheels
  const tireCorners = [['wheelFL', 'FL'], ['wheelFR', 'FR'], ['wheelBL', 'RL'], ['wheelBR', 'RR']]
  for (const [an, k] of tireCorners) {
    const d = el(`tire-${k}`, 'tire', '')
    const a = mode === 'tires' && tires ? anchor(an) : null
    if (!a) { d.classList.add('hide'); continue }
    const left = a.x < centreX
    const html = `<b>${tires[k] ?? '—'}<i>psi</i></b><small>${tires.ago ?? ''}</small>`
    if (d.innerHTML !== html) d.innerHTML = html
    place(d, left ? a.x - 28 : a.x + 28, a.y, left ? 'right' : 'left', true)
  }
}

// set up right away, so the app can send state before the Jeep has loaded
window.jeepEmbed = {
  apply(state = {}) {
    wanted = merge(wanted, state)
    if (typeof state.reducedMotion === 'boolean') {
      reducedMotion = state.reducedMotion || reducedMotion
      loader.still(reducedMotion)
      if (state.reducedMotion) toHero()   // Reduce Motion: no turn, straight to the 3/4 view
    }
    sync()
  },
  /** Turns the Jeep by `deg` (drag right: positive). */
  spin(deg) {
    if (!Number.isFinite(deg)) return
    stopGlide(); toHero(); turntable(false)
    if (mode === 'hero') setSpinFit(true, 300)
    setYaw(yaw + deg)
  },
  /** The drag ended: 2.5 s later the Jeep glides back (or the turntable turns on again). */
  release() {
    stopGlide()
    idle = setTimeout(() => { if (mode === 'turntable') turntable(true); else glideHome() }, 2500)
  },
  /** A vertical drag: the thumb follows the finger's pull `dy` (px, down positive) from `step`. */
  strip(dy, step) {
    if (!Number.isFinite(dy)) return
    stripEl.dataset.drag = '1'
    stripResidual = dy
    stripStep = Number.isInteger(step) ? Math.max(0, Math.min(STRIP_STEPS.length - 1, step)) : null
    placeStrip()
  },
  /** The vertical drag ended: the thumb snaps to the roof's step. */
  stripRelease() {
    delete stripEl.dataset.drag
    stripResidual = 0; stripStep = null
    placeStrip()
  },
  /** Two fingers: scale the view (1 … 1.8), relative to where the pinch began. */
  zoom(scale) {
    if (!Number.isFinite(scale)) return
    cancelAnimationFrame(zoomRaf); clearTimeout(zoomIdle)
    setZoom(scale)
  },
  zoomEnd() { clearTimeout(zoomIdle); zoomIdle = setTimeout(zoomHome, 2500) },
  /** The car's region, live (a divider drag): no animation. */
  layout(r) { if (r && Number.isFinite(r.x1)) setRegion(r, 0) },
  /** The drag let go: glide back to the region the app last applied. */
  layoutRelease() { if (regionWanted) setRegion(regionWanted, SLIDE_MS) },
}

// glossy black floor: a real reflection, faint, fading to fully transparent a short way out from the
// Jeep's footprint (so only the lower third of the car shows in it, and there is never an edge)
const FloorShader = {
  name: 'JeepFloor',
  uniforms: {
    color: { value: null }, tDiffuse: { value: null }, textureMatrix: { value: null },
    strength: { value: 0.25 },                      // how much of the Jeep the floor reflects
    glow: { value: new THREE.Color(0.05, 0.052, 0.058) }, // a faint pool of light under the car, so the shadow reads
    foot: { value: new THREE.Vector2(1, 2.4) },      // the footprint's half size (x across, z along), set from the model
    centre: { value: new THREE.Vector2(0, 0) },      // the footprint's centre, in the Jeep's own frame
    reach: { value: 0.7 },                           // the reflection is gone this far out from the footprint (m)
    yaw: { value: 0 },                               // the Jeep's spin, so the footprint turns with it
    light: { value: 0 },                             // 0 night … 1 day (cross-fades)
    dayFloor: { value: new THREE.Color(0.86, 0.86, 0.875) },  // day: pale grey glaze under the car (output colour)
    dayStrength: { value: 0.18 },                    // day: how much of the black Jeep the floor mirrors
  },
  vertexShader: /* glsl */`
    uniform mat4 textureMatrix;
    varying vec4 vUv;
    varying vec2 vXZ;
    #include <common>
    #include <logdepthbuf_pars_vertex>
    void main() {
      vUv = textureMatrix * vec4(position, 1.0);
      vXZ = (modelMatrix * vec4(position, 1.0)).xz;
      gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
      #include <logdepthbuf_vertex>
    }`,
  fragmentShader: /* glsl */`
    uniform vec3 color;
    uniform sampler2D tDiffuse;
    uniform float strength;
    uniform vec3 glow;
    uniform vec2 foot;
    uniform vec2 centre;
    uniform float reach;
    uniform float yaw;
    uniform float light;
    uniform vec3 dayFloor;
    uniform float dayStrength;
    varying vec4 vUv;
    varying vec2 vXZ;
    #include <logdepthbuf_pars_fragment>
    void main() {
      #include <logdepthbuf_fragment>
      // distance from the footprint (a rounded box in the Jeep's own frame; negative under the car)
      float c = cos(yaw), s = sin(yaw);
      vec2 p = vec2(c * vXZ.x - s * vXZ.y, s * vXZ.x + c * vXZ.y) - centre;
      vec2 q = abs(p) - foot;
      float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
      float fade = 1.0 - smoothstep(-0.15, reach, d);        // the reflection dies off close to the car
      float pool = 1.0 - smoothstep(-0.8, reach * 1.4, d);   // the light pool reaches a little further
      vec4 tex = texture2DProj(tDiffuse, vUv);
      vec3 refl = mix(tex.rgb, vec3(dot(tex.rgb, vec3(0.2126, 0.7152, 0.0722))), 0.85);  // a near-neutral reflection: no beige chassis showing

      // night: premultiplied, so on a black page this is exactly the colour; elsewhere a dark glaze
      gl_FragColor = vec4(refl * color * strength * fade * fade + glow * pool * pool, 1.0);
      #include <tonemapping_fragment>
      #include <colorspace_fragment>
      vec4 night = vec4(gl_FragColor.rgb, pool);

      // day: a pale grey glaze with the Jeep mirrored in it where the reflection has the car (alpha)
      gl_FragColor = vec4(refl * color, 1.0);
      #include <tonemapping_fragment>
      #include <colorspace_fragment>
      float cov = tex.a * dayStrength * fade * fade;
      float base = 0.55 * pool * pool;
      vec4 day = vec4(gl_FragColor.rgb * cov + dayFloor * base * (1.0 - cov), cov + base * (1.0 - cov));

      gl_FragColor = mix(night, day, light);
    }`,
}

// a soft dark footprint right under the body: the contact shadow that keeps the tyres on the ground
function contactShadow(w, l) {
  const c = document.createElement('canvas'); c.width = 256; c.height = 512
  const g = c.getContext('2d'); const pad = 70
  // draw the shape off-canvas and keep only its blurred shadow
  g.shadowColor = 'rgba(0,0,0,1)'; g.shadowBlur = 46; g.shadowOffsetX = 1000
  g.fillStyle = '#000'; g.beginPath(); g.roundRect(pad - 1000, pad, 256 - 2 * pad, 512 - 2 * pad, 40); g.fill()
  const tex = new THREE.CanvasTexture(c)
  const scale = 256 / (256 - 2 * pad)
  const m = new THREE.Mesh(new THREE.PlaneGeometry(w * scale, l * (512 / (512 - 2 * pad))), new THREE.MeshBasicMaterial({ map: tex, color: 0x000000, transparent: true, opacity: 1, depthWrite: false }))
  m.rotation.x = -Math.PI / 2
  return m
}

// a dark photo studio for the reflections: black walls, one long softbox overhead and a cool strip behind.
// Black paint then stays black and only picks up clean highlights, instead of mirroring a bright room.
function studio(renderer) {
  const room = new THREE.Scene()
  room.add(new THREE.Mesh(new THREE.SphereGeometry(30, 32, 16), new THREE.MeshBasicMaterial({ color: new THREE.Color(0.012, 0.012, 0.014), side: THREE.BackSide })))
  const panel = (w, h, rgb, k, pos, look) => {
    const m = new THREE.Mesh(new THREE.PlaneGeometry(w, h), new THREE.MeshBasicMaterial({ color: new THREE.Color(...rgb).multiplyScalar(k), side: THREE.DoubleSide }))
    m.position.set(...pos); m.lookAt(...look); room.add(m)
  }
  panel(1.2, 11, [1, 1, 1], 2.2, [0, 8, 0], [0, 0, 0])          // narrow softbox overhead, along the car (the top view's sheen)
  // three thin raised strips opposite the 3/4 camera: the roof slats and hood mirror them as crisp
  // silver streaks over black paint (thin, so the panels between them stay black)
  for (const [y, k] of [[6.4, 9], [7.6, 12], [8.8, 9]]) panel(13, 0.22, [1, 1, 1], k, [-7, y, -9], [0, 1, 0])
  panel(7, 2.2, [1, 1, 1], 0.9, [7, 3.5, 5], [0, 1, 0])           // front-right key, draws the hood and fender
  panel(9, 0.9, [0.8, 0.88, 1], 1.8, [-8, 1.6, -8], [0, 1, 0])    // cool strip low behind, the rim
  panel(14, 0.8, [1, 1, 1], 11, [-7, 0.7, 7], [0, 0.7, 0])       // long strip front-left at bumper height: the fender line
  const floor = new THREE.Mesh(new THREE.CircleGeometry(7, 48), new THREE.MeshBasicMaterial({ color: new THREE.Color(1.1, 1.1, 1.15) }))
  floor.rotation.x = -Math.PI / 2; floor.position.y = -0.6; room.add(floor)  // a lit studio floor, so the doors show their shape
  panel(14, 1.2, [1, 1, 1], 0.35, [0, 1.2, 12], [0, 1, 0])        // low horizon line, a thin highlight along the sides
  const pmrem = new THREE.PMREMGenerator(renderer)
  const tex = pmrem.fromScene(room, 0.03).texture
  pmrem.dispose()
  return tex
}

// ---------- framing: the whole Jeep, always, and big, inside its region ----------
// The camera fits the car's bounding boxes (spare tyre, mirrors and roof rack included) as they look on
// screen: their corners, projected from the view's own pitch (while spinning: turned to every 15° of
// a full spin, the union of all of them); that fills the car's box less 6% on every side, and is
// centred by shifting the view. The box is the region less the roof strip's column; the camera renders
// the canvas as a window of that box (a three.js view offset), so the car sits exactly in it.
const MARGIN = 0.05
const HERO_EL = 19   // the 3/4 view's pitch: a touch lower than the phone's, like Tesla's
const HERO_AZ = -38  // from the front and the driver's side (the charge port, the driver's door)
const SPIN_YAWS = Array.from({ length: 24 }, (_, i) => i * 15)
let corners = null   // the body's bounding box corners, Jeep frame
let boxY = 0         // the box's middle height: what the camera looks at

function fitView(name, v) {
  if (!corners) return null
  const w = canvas.clientWidth, h = canvas.clientHeight
  if (!w || !h) return null
  const box = carBox(region || fullRegion(), { strip: mode !== 'tires' })
  const rw = Math.max(1, box.x1 - box.x0), rh = Math.max(1, box.y1 - box.y0)
  const top = name === 'top'
  const yaws = (top ? mode === 'turntable' : spinFit) ? SPIN_YAWS : [0]
  const at = (az, el) => {
    const fit = fitBox(corners, { az, el, ty: boxY, fovDeg: 24, aspect: rw / rh, margin: MARGIN, yaws })
    // centre the union in the box: shift the view by where it landed (NDC → px), then show the
    // canvas as the window at (−box.x0, −box.y0) of the box
    return { d: fit.d, offset: [-box.x0 + (fit.cx * rw) / 2, -box.y0 + (-fit.cy * rh) / 2], full: [rw, rh] }
  }
  // fitAt: the glide between views frames every angle on its way too (top → 3/4 never clips)
  // the top views are front-up, like Tesla's
  const az = top ? 180 : name === 'hero' ? HERO_AZ : v.az, el = name === 'hero' ? HERO_EL : v.el
  return { ...at(az, el), az, el, y: boxY, fitAt: at }
}

const lerp = (a, b, k) => a + (b - a) * k

let viewName = 'hero'
function frameView(ms, name) {
  if (name) viewName = name
  jeep?.setView(viewName, ms)
}
function frameCam() {
  if (!jeep || !canvas.clientWidth || !canvas.clientHeight) return
  jeep.setView(viewName, 1)
  jeep.kick()
}

async function main() {
  // ?slow=1: hold the loading screen a while (for looking at it in the simulator)
  if (params.get('slow')) await new Promise((r) => setTimeout(r, 8000))
  const j = await createJeep(canvas, {
    url: new URL('model/jeep.glb', document.baseURI).href,
    onProgress: (p) => { loader.progress(p); post({ type: 'progress', value: p }) },
    onFrame: placeOverlay,
    fitView,
  })
  const scene = j.root.parent
  j.renderer.setClearColor(0x000000, 0)      // transparent: the window's colour shows through
  j.controls.enabled = false                 // CarPlay delivers no touches; nothing to orbit
  j.setNight(false)

  scene.environment = studio(j.renderer)

  // the body paint (and the hardtop's clones of it): night is glossy black with a clear coat, so the
  // studio's softboxes read as bright silver-white streaks; day keeps a satin metallic black
  const paints = new Set()
  j.root.traverse((o) => { if (o.isMesh) for (const m of [].concat(o.material)) if (m.name === 'JMI_1355060001_004') paints.add(m) })
  const coat = (k) => {
    for (const m of paints) {
      m.metalness = lerp(0.15, 0.55, k); m.roughness = lerp(0.1, 0.2, k)
      if (m.isMeshPhysicalMaterial) { m.clearcoat = lerp(1, 0, k); m.clearcoatRoughness = 0.04 }
    }
  }

  // the body's footprint (only the car's own meshes, not the headlight pools on the ground)
  const body = new THREE.Box3(); j.root.traverse((o) => { if (o.isMesh && o.castShadow) body.union(new THREE.Box3().setFromObject(o)) })
  const size = body.getSize(new THREE.Vector3()), mid = body.getCenter(new THREE.Vector3())

  const mirror = new Reflector(new THREE.PlaneGeometry(24, 24), { textureWidth: 1024, textureHeight: 1024, color: 0xffffff, clipBias: 0.002, shader: FloorShader })
  mirror.rotation.x = -Math.PI / 2; mirror.position.y = 0.0004
  Object.assign(mirror.material, { transparent: true, depthWrite: false, blending: THREE.CustomBlending, blendSrc: THREE.OneFactor, blendDst: THREE.OneMinusSrcAlphaFactor, blendSrcAlpha: THREE.OneFactor, blendDstAlpha: THREE.OneMinusSrcAlphaFactor })
  mirror.renderOrder = 1
  scene.add(mirror)
  floor = mirror.material.uniforms
  floor.foot.value.set(size.x / 2, size.z / 2)
  floor.centre.value.set(mid.x, mid.z)
  floor.reach.value = size.y * 0.35
  // the key light's shadow sits on top of the mirror, then the contact footprint on top of that
  scene.traverse((o) => { if (o.isMesh && o.material?.type === 'ShadowMaterial') { o.position.y = 0.003; o.material.opacity = 0.5; o.renderOrder = 2 } })
  const shadows = []; scene.traverse((o) => { if (o.isMesh && o.material?.type === 'ShadowMaterial') shadows.push(o.material) })
  // the contact footprint turns with the Jeep (spin turns the root)
  const contact = contactShadow(size.x * 1.02, size.z * 0.98); contact.position.set(mid.x, 0.005, mid.z); contact.renderOrder = 3; j.root.add(contact)

  // studio light for black paint: a softer key so the body stays black, and a cool rim light
  // that draws its edges against the black page, like Tesla's renders
  scene.traverse((o) => { if (o.isDirectionalLight && o.castShadow) o.intensity = 1.1 })
  j.renderer.toneMappingExposure = 1.1
  const rim = new THREE.DirectionalLight(0xcfe0ff, 2.6); rim.position.set(-6, 2.6, -7); scene.add(rim)
  // day: a soft overhead sky light so the black paint reads glossy, with clean highlights, not a hole in the page
  const sky = new THREE.HemisphereLight(0xffffff, 0xd8d8dc, 0); scene.add(sky)
  const key = []; scene.traverse((o) => { if (o.isDirectionalLight && o.castShadow) key.push(o) })
  const fill = []; scene.traverse((o) => { if (o.isDirectionalLight && !o.castShadow && o !== rim) fill.push([o, o.intensity]) })

  // night ↔ day: floor, shadows and lights cross-fade over 300 ms (instant the first time)
  let themeK = 0, themeRaf = 0
  // the top views at night lift the light a little (`liftK`), so the black roof reads on black
  let liftK = 0, liftRaf = 0
  function paintTheme(k) {
    themeK = k
    coat(k)
    const lift = liftK * (1 - k)
    mirror.material.uniforms.light.value = k
    contact.material.opacity = lerp(1, 0.5, k)
    for (const m of shadows) m.opacity = lerp(0.5, 0.18, k)
    for (const l of key) l.intensity = lerp(1.1, 2.4, k) + lift * 1.8
    for (const [l, i] of fill) l.intensity = i * lerp(1, 2.2, k) * (1 + lift * 0.6)
    rim.intensity = lerp(2.6, 1.2, k)
    sky.intensity = lerp(0, 0.9, k) + lift * 1.1
    scene.environmentIntensity = lerp(1, 1.5, k) + lift * 0.9
    j.renderer.toneMappingExposure = lerp(1.1, 1.0, k) + lift * 0.4
    j.kick()
  }
  j.setLift = (to) => {
    cancelAnimationFrame(liftRaf)
    const from = liftK
    if (reducedMotion) { liftK = to; paintTheme(themeK); return }
    const t0 = performance.now()
    const step = (t) => { const k = Math.min(1, (t - t0) / 600); liftK = lerp(from, to, k); paintTheme(themeK); liftRaf = k < 1 ? requestAnimationFrame(step) : 0 }
    liftRaf = requestAnimationFrame(step)
  }
  let themed = false
  j.setTheme = (name) => {
    const to = name === 'light' ? 1 : 0, from = themeK
    cancelAnimationFrame(themeRaf)
    if (!themed || reducedMotion) { themed = true; paintTheme(to); return }
    const t0 = performance.now()
    const step = (t) => { const k = Math.min(1, (t - t0) / 300); paintTheme(lerp(from, to, k)); themeRaf = k < 1 ? requestAnimationFrame(step) : 0 }
    themeRaf = requestAnimationFrame(step)
  }
  j.setTheme(wanted.theme === 'light' ? 'light' : 'dark'); shown.theme = wanted.theme === 'light' ? 'light' : 'dark'
  themed = true

  // frame the whole car (see fitView): the body's box, at no spin
  // each part's own box corners, not just the whole body's: the whole box's empty top corners (over
  // the low hood, behind the roof) would shrink the car for nothing. Still never inside the real outline.
  corners = []
  j.root.traverse((o) => { if (o.isMesh && o.castShadow) { const b = new THREE.Box3().setFromObject(o); if (!b.isEmpty()) corners.push(...boxCorners(b.min.toArray(), b.max.toArray())) } })
  boxY = mid.y
  const setView = j.setView
  j.setView = (name, ms) => { viewName = name; setView(name, ms) }
  if (!region) region = regionWanted ?? fullRegion()
  const onResize = () => { if (!regionWanted) region = fullRegion(); frameCam(); placeStrip() }
  frameCam(); new ResizeObserver(onResize).observe(canvas)

  jeep = j; window.__jeep = j
  setYaw(yaw)
  sync()
  if (mode !== 'hero') { const m = mode; mode = 'hero'; setMode(m) }

  // open from above, then one ease-in-out turn to the three-quarter view
  const start = params.get('view') || 'top'
  if (mode !== 'hero') { settled = true }
  else if (start === 'top' && params.get('settle') === '0') j.setView('top', 1)   // for checking the top view
  else if (start === 'top' && !reducedMotion) { j.setView('top', 1); settle = setTimeout(toHero, 1400) }
  else { settled = true; j.setView(start === 'top' ? 'hero' : start, 1) }   // Reduce Motion: straight to 3/4
  j.kick()

  // ready once the first frame is on screen: the loader fades into the Jeep
  requestAnimationFrame(() => requestAnimationFrame(() => {
    document.documentElement.dataset.ready = '1'
    loader.done()
    placeStrip(); placeOverlay()
    post({ type: 'ready' })
  }))
}
main().catch((e) => post({ type: 'error', message: String(e) }))
