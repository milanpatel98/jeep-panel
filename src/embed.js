// The 3D Jeep on its own, for the CarPlay screen's left panel (loaded in a web view).
// Black Jeep on a faint mirror floor that fades out to nothing; the page itself is transparent.
// It opens from above and makes one slow turn to the three-quarter view; nothing else moves on its own.
// The app drives it with window.jeepEmbed.apply(state); there is no touch (CarPlay sends none).
import * as THREE from 'three'
import { Reflector } from 'three/addons/objects/Reflector.js'
import { createJeep } from './jeep.js'
import { embedCalls } from './embedState.js'

const canvas = document.getElementById('c')
const params = new URLSearchParams(location.search)
const post = (msg) => window.webkit?.messageHandlers?.jeep?.postMessage(msg)

const DEFAULTS = { lights: false, roof: 'on', doors: { FL: false, FR: false, BL: false, BR: false }, gate: false }
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
  if (!jeep) return
  for (const [method, ...args] of embedCalls(shown, wanted)) jeep[method](...args)
  shown = merge(shown, wanted)
}

// set up right away, so the app can send state before the Jeep has loaded
window.jeepEmbed = {
  apply(state = {}) {
    wanted = merge(wanted, state)
    if (typeof state.reducedMotion === 'boolean') {
      reducedMotion = state.reducedMotion || reducedMotion
      if (state.reducedMotion) toHero()   // Reduce Motion: no turn, straight to the 3/4 view
    }
    sync()
  },
}

// glossy black floor: a real reflection, faint, fading to fully transparent away from the Jeep (no edge)
const FloorShader = {
  name: 'JeepFloor',
  uniforms: {
    color: { value: null }, tDiffuse: { value: null }, textureMatrix: { value: null },
    strength: { value: 0.3 },                       // how much of the Jeep the floor reflects
    glow: { value: new THREE.Color(0.08, 0.083, 0.09) }, // a faint pool of light under the car, so the shadow reads
    radius: { value: new THREE.Vector2(2.7, 4.0) },  // fade ellipse (x across the car, z along it)
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
    varying vec4 vUv;
    varying vec2 vXZ;
    #include <logdepthbuf_pars_fragment>
    void main() {
      #include <logdepthbuf_fragment>
      float r = length(vXZ / radius);
      float fade = 1.0 - smoothstep(0.35, 1.0, r);   // reflection dies off near the car
      float pool = 1.0 - smoothstep(0.0, 1.05, r);   // the light pool reaches a little further
      vec3 refl = texture2DProj(tDiffuse, vUv).rgb;
      refl = mix(refl, vec3(dot(refl, vec3(0.2126, 0.7152, 0.0722))), 0.85);  // a near-neutral reflection: no beige chassis showing
      refl *= color * strength * fade * fade;
      gl_FragColor = vec4(refl + glow * pool * pool, 1.0);
      #include <tonemapping_fragment>
      #include <colorspace_fragment>
      // premultiplied: on a black page this is exactly the colour above; on anything else the floor is a dark glaze
      gl_FragColor.a = pool;
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
  const contact = contactShadow(size.x * 1.02, size.z * 0.98); contact.position.set(mid.x, 0.005, mid.z); contact.renderOrder = 3; scene.add(contact)

  // studio light for black paint: a softer key so the body stays black, and a cool rim light
  // that draws its edges against the black page, like Tesla's renders
  scene.traverse((o) => { if (o.isDirectionalLight && o.castShadow) o.intensity = 1.1 })
  j.renderer.toneMappingExposure = 0.9
  const rim = new THREE.DirectionalLight(0xcfe0ff, 2.6); rim.position.set(-6, 2.6, -7); scene.add(rim)

  jeep = j
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
