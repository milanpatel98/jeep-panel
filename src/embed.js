// The 3D Jeep on its own, for the CarPlay screen's left panel (loaded in a web view).
// Black Jeep on a faint mirror floor that fades out to nothing; the page itself is transparent.
// It opens from above and makes one slow turn to the three-quarter view; nothing else moves on its own.
// The app drives it with window.jeepEmbed: apply(state), spin(deg) / release() for a horizontal drag,
// strip(pos) / stripRelease(step) for a vertical one (the roof strip). The page itself takes no touches.
import * as THREE from 'three'
import { Reflector } from 'three/addons/objects/Reflector.js'
import { createJeep } from './jeep.js'
import { embedCalls, stripStep, shortestTurn, fitBox, boxCorners, STRIP_STEPS } from './embedState.js'

const canvas = document.getElementById('c')
const params = new URLSearchParams(location.search)
const post = (msg) => window.webkit?.messageHandlers?.jeep?.postMessage(msg)

const DEFAULTS = { theme: 'dark', lights: false, roof: 'on', doorsOff: false, doors: { FL: false, FR: false, BL: false, BR: false }, gate: false }
let shown = structuredClone(DEFAULTS)   // what the 3D Jeep shows now
let wanted = {}                         // everything the app has asked for so far
let jeep = null
let reducedMotion = !!window.matchMedia?.('(prefers-reduced-motion: reduce)').matches
let settle = 0, settled = false

const merge = (a, b) => ({ ...a, ...b, ...(b.doors ? { doors: { ...a.doors, ...b.doors } } : {}) })

function toHero() {
  clearTimeout(settle)
  if (settled || !jeep) return
  settled = true
  jeep.setView('hero', reducedMotion ? 1 : 1600)
}

function sync() {
  const theme = wanted.theme === 'light' ? 'light' : 'dark'
  document.documentElement.dataset.theme = theme      // the roof strip follows at once
  if (!dragging) placeStrip(stripStep(merge(shown, wanted)), false)
  if (!jeep) return
  for (const [method, ...args] of embedCalls(shown, wanted)) jeep[method](...args)
  shown = merge(shown, wanted)
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
  if (jeep && settled) jeep.setView('hero', reducedMotion ? 1 : ms)
}
function glideHome() {
  stopGlide()
  const from = shortestTurn(yaw)
  if (reducedMotion || Math.abs(from) < 0.05) { setYaw(0); setSpinFit(false, 500); return }
  const t0 = performance.now()
  const step = (t) => {
    const k = Math.min(1, (t - t0) / 900)
    setYaw(from * (1 - ease(k)))
    glideRaf = k < 1 ? requestAnimationFrame(step) : 0
    if (k >= 1) setSpinFit(false, 500)
  }
  glideRaf = requestAnimationFrame(step)
}

// ---------- roof strip: a dotted track with a little Jeep-top thumb at the current step ----------
const stripEl = document.getElementById('strip')
const puckEl = document.getElementById('puck')
const labelEl = document.getElementById('strip-label')
const GLYPHS = [
  '<rect x="7" y="13" width="18" height="26" rx="3" fill="currentColor" opacity=".9"/>',   // top on
  '<rect x="7" y="23" width="18" height="16" rx="3" fill="currentColor" opacity=".9"/>',   // panels off: rear half stays
  '',                                                                                      // top off
  '',                                                                                      // doors off
]
const BODY = '<rect x="3" y="2" width="26" height="52" rx="9" fill="none" stroke="currentColor" stroke-width="2"/>'
// doors off: the body outline with its sides open where the doors were
const NO_DOORS = '<path d="M3 17V11a9 9 0 0 1 9-9h8a9 9 0 0 1 9 9v6M3 41v4a9 9 0 0 0 9 9h8a9 9 0 0 0 9-9v-4" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>'
const glyph = (i) => `<svg viewBox="0 0 32 56" aria-hidden="true">${i === 3 ? NO_DOORS : BODY}${GLYPHS[i]}<path d="M8 8h16" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>`
let shownGlyph = -1, dragging = false
function placeStrip(pos, live) {
  const max = STRIP_STEPS.length - 1
  const i = Math.round(Math.min(max, Math.max(0, pos)))
  stripEl.classList.toggle('live', live)
  stripEl.style.setProperty('--pos', String(Math.min(max, Math.max(0, pos)) / max))
  if (i !== shownGlyph) {
    shownGlyph = i; puckEl.innerHTML = glyph(i); labelEl.textContent = STRIP_STEPS[i].label
    // a label wider than the strip ("Doors off") moves left so it never runs off the page
    labelEl.style.marginLeft = `${-Math.max(0, labelEl.offsetWidth / 2 - (stripEl.offsetWidth / 2 - 2))}px`
  }
}

// set up right away, so the app can send state before the Jeep has loaded
window.jeepEmbed = {
  apply(state = {}) {
    wanted = merge(wanted, state)
    if (typeof state.reducedMotion === 'boolean') {
      reducedMotion = state.reducedMotion || reducedMotion
      document.documentElement.classList.toggle('reduce', reducedMotion)
      if (state.reducedMotion) toHero()   // Reduce Motion: no turn, straight to the 3/4 view
    }
    sync()
  },
  /** Turns the Jeep by `deg` (drag right: positive). */
  spin(deg) {
    if (!Number.isFinite(deg)) return
    stopGlide(); toHero(); setSpinFit(true, 300)
    setYaw(yaw + deg)
  },
  /** The drag ended: 2.5 s later the Jeep glides back to the 3/4 view. */
  release() {
    stopGlide()
    idle = setTimeout(glideHome, 2500)
  },
  /** The thumb follows the finger: `pos` is a step, fractional while dragging (0 top on … 3 doors off). */
  strip(pos) {
    if (!Number.isFinite(pos)) return
    dragging = true
    placeStrip(pos, true)
  },
  /** The finger lifted: the thumb springs to `step`; the app sends the matching roof next. */
  stripRelease(step) {
    dragging = false
    placeStrip(Number.isFinite(step) ? step : stripStep(merge(shown, wanted)), false)
  },
}
placeStrip(0, false)

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

// ---------- framing: the whole Jeep, always, and big ----------
// The camera fits the car's bounding boxes (spare tyre, mirrors and roof rack included) as they look on
// screen: their corners, projected from the view's own pitch (while spinning: turned to every 15° of
// a full spin, the union of all of them); that fills the area left of the roof strip less 6% on every side, and is centred
// there by shifting the view. So the 3/4 view is as big as it can be and no spin ever clips it.
// At rest (the 3/4 view, the top view) it fits only that one angle, so the car is big; while a drag
// turns it, the camera eases back to the fit for every angle (setSpinFit).
// STRIP_W: what the car's area leaves free on the right. Less than the strip's 44 px, so the car sits
// right up against the puck (its rear just tucks under the strip's left edge, like the mockup)
// instead of leaving a gap by the map card.
const STRIP_W = 28, MARGIN = 0.06
const SPIN_YAWS = Array.from({ length: 24 }, (_, i) => i * 15)
let corners = null   // the body's bounding box corners, Jeep frame
let boxY = 0         // the box's middle height: what the camera looks at

function fitView(name, v) {
  if (!corners) return null
  const w = canvas.clientWidth, h = canvas.clientHeight
  if (!w || !h) return null
  // the top view is wider than the 3/4 view: it stops 4 px short of the puck, wherever the 3/4 view put it
  const puckLeft = stripEl.getBoundingClientRect().left + (stripEl.offsetWidth - 30) / 2
  const free = name === 'top' ? Math.max(STRIP_W, w - puckLeft + 4) : STRIP_W
  const area = Math.max(1, w - free)
  const yaws = spinFit && name !== 'top' ? SPIN_YAWS : [0]
  const at = (az, el) => {
    const fit = fitBox(corners, { az, el, ty: boxY, fovDeg: 24, aspect: area / h, margin: MARGIN, yaws })
    // centre the union in the area: shift the view by where it landed (NDC → px), plus half the strip
    return { d: fit.d, offset: [free / 2 + (fit.cx * area) / 2, (-fit.cy * h) / 2], right: area / 2 + (fit.hx * area) / 2 }
  }
  // the roof strip hugs the car at rest in the 3/4 view: its puck's left edge 6 px off the car's right
  if (name === 'hero' && !spinFit) {
    const right = at(v.az, v.el).right
    stripEl.style.right = `${Math.max(0, w - (right + 6 + 15) - 22)}px`
  }
  // fitAt: the glide between views frames every angle on its way too (top → 3/4 never clips)
  return { ...at(v.az, v.el), y: boxY, fitAt: at }
}

const lerp = (a, b, k) => a + (b - a) * k

async function main() {
  const j = await createJeep(canvas, {
    url: new URL('model/jeep.glb', document.baseURI).href,
    onProgress: (p) => post({ type: 'progress', value: p }),
    fitView,
  })
  const scene = j.root.parent
  j.renderer.setClearColor(0x000000, 0)      // transparent: the panel's black shows through
  j.controls.enabled = false                 // CarPlay delivers no touches; nothing to orbit
  j.setNight(false)

  scene.environment = studio(j.renderer)

  // the body paint (and the hardtop's clones of it): night is glossy black with a clear coat, so the
  // studio's softboxes read as bright silver-white streaks; day keeps pass 1's satin metallic black
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
  function paintTheme(k) {
    themeK = k
    coat(k)
    mirror.material.uniforms.light.value = k
    contact.material.opacity = lerp(1, 0.5, k)
    for (const m of shadows) m.opacity = lerp(0.5, 0.18, k)
    for (const l of key) l.intensity = lerp(1.1, 2.4, k)
    for (const [l, i] of fill) l.intensity = i * lerp(1, 2.2, k)
    rim.intensity = lerp(2.6, 1.2, k)
    sky.intensity = lerp(0, 0.9, k)
    scene.environmentIntensity = lerp(1, 1.5, k)
    j.renderer.toneMappingExposure = lerp(1.1, 1.0, k)
    j.kick()
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
  let viewName = 'hero'
  const setView = j.setView
  j.setView = (name, ms) => { viewName = name; setView(name, ms) }
  const frameCam = () => {
    if (!canvas.clientWidth || !canvas.clientHeight) return
    j.cam.zoom = 1
    setView(viewName, 1)
    j.kick()
  }
  frameCam(); new ResizeObserver(frameCam).observe(canvas)

  jeep = j
  setYaw(yaw)
  sync()

  // open from above, then one ease-in-out turn to the three-quarter view
  const start = params.get('view') || 'top'
  if (start === 'top' && params.get('settle') === '0') j.setView('top', 1)   // for checking the top view
  else if (start === 'top' && !reducedMotion) { j.setView('top', 1); settle = setTimeout(toHero, 2400) }
  else { settled = true; j.setView(start === 'top' ? 'hero' : start, 1) }   // Reduce Motion: straight to 3/4
  j.kick()

  post({ type: 'ready' })
}
main().catch((e) => post({ type: 'error', message: String(e) }))
