// The 3D Jeep on its own, for the CarPlay screen's left panel (loaded in a web view).
// Black Jeep on a faint mirror floor that fades out to nothing; the page itself is transparent.
// It opens from above and makes one slow turn to the three-quarter view; nothing else moves on its own.
// The app drives it with window.jeepEmbed: apply(state), spin(deg) / release() for a horizontal drag,
// strip(pos) / stripRelease(step) for a vertical one (the roof strip). The page itself takes no touches.
import * as THREE from 'three'
import { Reflector } from 'three/addons/objects/Reflector.js'
import { createJeep } from './jeep.js'
import { embedCalls, stripStep, shortestTurn, STRIP_STEPS } from './embedState.js'

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
function setYaw(deg) {
  yaw = deg
  if (!jeep) return
  jeep.root.rotation.y = THREE.MathUtils.degToRad(deg)
  jeep.kick()
}
function stopGlide() { cancelAnimationFrame(glideRaf); glideRaf = 0; clearTimeout(idle) }
function glideHome() {
  stopGlide()
  const from = shortestTurn(yaw)
  if (reducedMotion || Math.abs(from) < 0.05) { setYaw(0); return }
  const t0 = performance.now()
  const step = (t) => {
    const k = Math.min(1, (t - t0) / 900)
    setYaw(from * (1 - ease(k)))
    glideRaf = k < 1 ? requestAnimationFrame(step) : 0
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
  stripEl.style.setProperty('--pos', String(pos / max))
  if (i !== shownGlyph) { shownGlyph = i; puckEl.innerHTML = glyph(i); labelEl.textContent = STRIP_STEPS[i].label }
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
    stopGlide(); toHero()
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

// glossy black floor: a real reflection, faint, fading to fully transparent away from the Jeep (no edge)
const FloorShader = {
  name: 'JeepFloor',
  uniforms: {
    color: { value: null }, tDiffuse: { value: null }, textureMatrix: { value: null },
    strength: { value: 0.3 },                       // how much of the Jeep the floor reflects
    glow: { value: new THREE.Color(0.08, 0.083, 0.09) }, // a faint pool of light under the car, so the shadow reads
    radius: { value: new THREE.Vector2(2.7, 4.0) },  // fade ellipse (x across the car, z along it)
    light: { value: 0 },                             // 0 night … 1 day (cross-fades)
    dayFloor: { value: new THREE.Color(0.86, 0.86, 0.875) },  // day: pale grey glaze under the car (output colour)
    dayStrength: { value: 0.34 },                    // day: how much of the black Jeep the floor mirrors
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
    uniform vec2 radius;
    uniform float light;
    uniform vec3 dayFloor;
    uniform float dayStrength;
    varying vec4 vUv;
    varying vec2 vXZ;
    #include <logdepthbuf_pars_fragment>
    void main() {
      #include <logdepthbuf_fragment>
      float r = length(vXZ / radius);
      float fade = 1.0 - smoothstep(0.35, 1.0, r);   // reflection dies off near the car
      float pool = 1.0 - smoothstep(0.0, 1.05, r);   // the light pool reaches a little further
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
  panel(2, 9, [1, 1, 1], 2.2, [0, 9, 0], [0, 0, 0])               // softbox overhead, along the car
  panel(7, 2.2, [1, 1, 1], 0.9, [7, 3.5, 5], [0, 1, 0])           // front-right key, draws the hood and fender
  panel(9, 0.9, [0.8, 0.88, 1], 1.8, [-8, 1.6, -8], [0, 1, 0])    // cool strip low behind, the rim
  const floor = new THREE.Mesh(new THREE.CircleGeometry(7, 48), new THREE.MeshBasicMaterial({ color: new THREE.Color(1.1, 1.1, 1.15) }))
  floor.rotation.x = -Math.PI / 2; floor.position.y = -0.6; room.add(floor)  // a lit studio floor, so the doors show their shape
  panel(14, 1.2, [1, 1, 1], 0.35, [0, 1.2, 12], [0, 1, 0])        // low horizon line, a thin highlight along the sides
  const pmrem = new THREE.PMREMGenerator(renderer)
  const tex = pmrem.fromScene(room, 0.03).texture
  pmrem.dispose()
  return tex
}

async function main() {
  const j = await createJeep(canvas, {
    url: new URL('model/jeep.glb', document.baseURI).href,
    onProgress: (p) => post({ type: 'progress', value: p }),
  })
  const scene = j.root.parent
  j.renderer.setClearColor(0x000000, 0)      // transparent: the panel's black shows through
  j.controls.enabled = false                 // CarPlay delivers no touches; nothing to orbit
  j.setNight(false)

  scene.environment = studio(j.renderer)

  // the body's footprint (only the car's own meshes, not the headlight pools on the ground)
  const body = new THREE.Box3(); j.root.traverse((o) => { if (o.isMesh && o.castShadow) body.union(new THREE.Box3().setFromObject(o)) })
  const size = body.getSize(new THREE.Vector3()), mid = body.getCenter(new THREE.Vector3())

  const mirror = new Reflector(new THREE.PlaneGeometry(24, 24), { textureWidth: 1024, textureHeight: 1024, color: 0xffffff, clipBias: 0.002, shader: FloorShader })
  mirror.rotation.x = -Math.PI / 2; mirror.position.y = 0.0004
  Object.assign(mirror.material, { transparent: true, depthWrite: false, blending: THREE.CustomBlending, blendSrc: THREE.OneFactor, blendDst: THREE.OneMinusSrcAlphaFactor, blendSrcAlpha: THREE.OneFactor, blendDstAlpha: THREE.OneMinusSrcAlphaFactor })
  mirror.renderOrder = 1
  scene.add(mirror)
  // the key light's shadow sits on top of the mirror, then the contact footprint on top of that
  scene.traverse((o) => { if (o.isMesh && o.material?.type === 'ShadowMaterial') { o.position.y = 0.003; o.material.opacity = 0.5; o.renderOrder = 2 } })
  const shadows = []; scene.traverse((o) => { if (o.isMesh && o.material?.type === 'ShadowMaterial') shadows.push(o.material) })
  // the contact footprint turns with the Jeep (spin turns the root)
  const contact = contactShadow(size.x * 1.02, size.z * 0.98); contact.position.set(mid.x, 0.005, mid.z); contact.renderOrder = 3; j.root.add(contact)

  // studio light for black paint: a softer key so the body stays black, and a cool rim light
  // that draws its edges against the black page, like Tesla's renders
  scene.traverse((o) => { if (o.isDirectionalLight && o.castShadow) o.intensity = 1.1 })
  j.renderer.toneMappingExposure = 0.9
  const rim = new THREE.DirectionalLight(0xcfe0ff, 2.6); rim.position.set(-6, 2.6, -7); scene.add(rim)
  // day: a soft overhead sky light so the black paint reads glossy, with clean highlights, not a hole in the page
  const sky = new THREE.HemisphereLight(0xffffff, 0xd8d8dc, 0); scene.add(sky)
  const key = []; scene.traverse((o) => { if (o.isDirectionalLight && o.castShadow) key.push(o) })
  const fill = []; scene.traverse((o) => { if (o.isDirectionalLight && !o.castShadow && o !== rim) fill.push([o, o.intensity]) })

  // night ↔ day: floor, shadows and lights cross-fade over 300 ms (instant the first time)
  const lerp = (a, b, k) => a + (b - a) * k
  let themeK = 0, themeRaf = 0
  function paintTheme(k) {
    themeK = k
    mirror.material.uniforms.light.value = k
    contact.material.opacity = lerp(1, 0.5, k)
    for (const m of shadows) m.opacity = lerp(0.5, 0.18, k)
    for (const l of key) l.intensity = lerp(1.1, 2.4, k)
    for (const [l, i] of fill) l.intensity = i * lerp(1, 2.2, k)
    rim.intensity = lerp(2.6, 1.2, k)
    sky.intensity = lerp(0, 0.9, k)
    scene.environmentIntensity = lerp(1, 1.5, k)
    j.renderer.toneMappingExposure = lerp(0.9, 1.0, k)
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

  // a closer camera: the Jeep fills its frame (about 15% bigger than the phone's fit), set a touch
  // left of centre and up, so the roof strip on the right has its own room and there's no empty band on top
  j.cam.zoom = Number(params.get('zoom')) || 1.22
  const frameCam = () => {
    const w = canvas.clientWidth, h = canvas.clientHeight
    if (!w || !h) return
    j.cam.setViewOffset(w, h, w * 0.035, h * 0.03, w, h)
    j.cam.updateProjectionMatrix(); j.kick()
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
