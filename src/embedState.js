// What the CarPlay 3D Jeep has to do to get from one state to the next.
// Pure: returns the createJeep calls for what changed, nothing for what didn't.
// Anything prev leaves out counts as the default: lights off, roof on, doors on and closed, gate closed, dark theme.
const ROOFS = ['on', 'panels', 'off']
const DOOR_KEYS = ['FL', 'FR', 'BL', 'BR']
const THEMES = ['dark', 'light']

export function embedCalls(prev = {}, next = {}) {
  const calls = []
  if (THEMES.includes(next.theme) && next.theme !== (prev.theme ?? 'dark')) calls.push(['setTheme', next.theme])
  if (typeof next.lights === 'boolean' && next.lights !== !!prev.lights) calls.push(['setLights', next.lights])
  if (ROOFS.includes(next.roof) && next.roof !== (prev.roof ?? 'on')) calls.push(['setRoof', next.roof])
  if (typeof next.doorsOff === 'boolean' && next.doorsOff !== !!prev.doorsOff) calls.push(['setDoorsOff', next.doorsOff])
  if (next.doors) {
    for (const k of DOOR_KEYS) {
      const open = next.doors[k]
      if (typeof open === 'boolean' && open !== !!prev.doors?.[k]) calls.push(['setDoor', k, open])
    }
  }
  if (typeof next.gate === 'boolean' && next.gate !== !!prev.gate) calls.push(['setGate', next.gate])
  return calls
}

// After a spin, the turn left over, in degrees, wrapped into (-180, 180]: the glide back takes the short way.
export function shortestTurn(deg) {
  let d = deg % 360
  if (d > 180) d -= 360
  if (d <= -180) d += 360
  return d
}

// Frames a box so it looks as big as it can without ever leaving the frame while it turns.
// The camera looks at (0, ty, 0) from azimuth `az` and elevation `el` (degrees, like the Jeep's views);
// the box's 8 `corners` ([x, y, z]) are turned about the vertical axis by every angle in `yaws`
// (degrees) and projected; the union of their screen extents fills the frame less `margin` on every
// side. `aspect` is the frame's width / height and `fovDeg` the vertical field of view.
// Returns the distance `d`, where the union's centre lands (`cx`, `cy`, in -1…1 of the frame, y up),
// so the caller can shift the view to centre it, and its half size (`hx`, `hy`, same units).
export function fitBox(corners, { az, el, ty = 0, fovDeg, aspect, margin = 0, yaws = [0] }) {
  const rad = Math.PI / 180
  const dir = [Math.cos(el * rad) * Math.sin(az * rad), Math.sin(el * rad), Math.cos(el * rad) * Math.cos(az * rad)]
  const f = dir.map((c) => -c)
  // right = f × up(0, 1, 0), up' = right × f
  let r = [-f[2], 0, f[0]]; const rl = Math.hypot(r[0], r[2]) || 1; r = r.map((c) => c / rl)
  const u = [r[1] * f[2] - r[2] * f[1], r[2] * f[0] - r[0] * f[2], r[0] * f[1] - r[1] * f[0]]
  const tanV = Math.tan((fovDeg * rad) / 2), tanH = tanV * aspect
  const pts = []
  for (const yaw of yaws) {
    const c = Math.cos(yaw * rad), s = Math.sin(yaw * rad)
    for (const [x, y, z] of corners) pts.push([x * c + z * s, y - ty, -x * s + z * c])
  }
  const extents = (d) => {
    let x0 = Infinity, x1 = -Infinity, y0 = Infinity, y1 = -Infinity
    for (const p of pts) {
      const v = [p[0] - dir[0] * d, p[1] - dir[1] * d, p[2] - dir[2] * d]
      const z = v[0] * f[0] + v[1] * f[1] + v[2] * f[2]
      const x = (v[0] * r[0] + v[1] * r[1] + v[2] * r[2]) / (z * tanH)
      const y = (v[0] * u[0] + v[1] * u[1] + v[2] * u[2]) / (z * tanV)
      x0 = Math.min(x0, x); x1 = Math.max(x1, x); y0 = Math.min(y0, y); y1 = Math.max(y1, y)
    }
    return { x0, x1, y0, y1, half: Math.max((x1 - x0) / 2, (y1 - y0) / 2) }
  }
  const want = 1 - 2 * Math.min(Math.max(margin, 0), 0.45)
  let lo = Math.max(...pts.map((p) => Math.hypot(...p))) * 1.05, hi = lo * 40
  for (let i = 0; i < 32; i++) {
    const mid = (lo + hi) / 2
    if (extents(mid).half > want) lo = mid; else hi = mid
  }
  const e = extents(hi)
  return { d: hi, cx: (e.x0 + e.x1) / 2, cy: (e.y0 + e.y1) / 2, hx: (e.x1 - e.x0) / 2, hy: (e.y1 - e.y0) / 2 }
}

// The 8 corners of a box given by its min and max ([x, y, z]).
export function boxCorners(min, max) {
  const out = []
  for (const x of [min[0], max[0]]) for (const y of [min[1], max[1]]) for (const z of [min[2], max[2]]) out.push([x, y, z])
  return out
}

// ---------- v2: the overlay (call-outs, roof strip, tires), the car's region and the views ----------

// The roof strip's steps, bottom to top: dragging up takes parts off one step at a time.
export const STRIP_STEPS = ['on', 'panels', 'off', 'doorsOff']
export const STRIP_PITCH = 44

// Which step the Jeep is on (0 = Top on … 3 = Doors off).
export function stripIndex(roof, doorsOff) {
  if (doorsOff) return 3
  const i = STRIP_STEPS.indexOf(roof)
  return i < 0 ? 0 : i
}

// Where the thumb's centre sits on a track whose top step is at `top`: step `index` (bottom = 0),
// plus the finger's residual pull `residual` (px, down positive) while a drag is on, never past the ends.
export function stripThumbY(index, residual = 0, { top = 0, pitch = STRIP_PITCH, steps = STRIP_STEPS.length } = {}) {
  const span = (steps - 1) * pitch
  const y = top + (steps - 1 - index) * pitch + residual
  return Math.min(top + span, Math.max(top, y))
}

// The views the Jeep button cycles: the 3/4 hero, the top view turning on its own, the tires.
export const MODES = ['hero', 'turntable', 'tires']
export function nextMode(mode) {
  const i = MODES.indexOf(mode)
  return MODES[(i + 1) % MODES.length]
}

// What the overlay has to do to get from one state to the next (like embedCalls, for the page's own
// parts rather than the 3D model). `region` and `tires` compare by value.
const same = (a, b) => JSON.stringify(a ?? null) === JSON.stringify(b ?? null)
export function overlayCalls(prev = {}, next = {}) {
  const calls = []
  if (MODES.includes(next.mode) && next.mode !== (prev.mode ?? 'hero')) calls.push(['setMode', next.mode])
  const fresh = (k) => k in next && (!(k in prev) || (next[k] ?? null) !== (prev[k] ?? null))
  if (fresh('locked')) calls.push(['setLock', next.locked ?? null])
  if (fresh('charge')) calls.push(['setCharge', next.charge ?? null])
  if (next.tires && !same(next.tires, prev.tires)) calls.push(['setTires', next.tires])
  if (next.region && !same(next.region, prev.region)) calls.push(['setRegion', next.region])
  return calls
}

// The box the car is fitted into: the region less the strip's column on its right (when the strip shows).
export function carBox(region, { strip = true, stripWidth = 48 } = {}) {
  const x1 = strip ? Math.max(region.x0 + 1, region.x1 - stripWidth) : region.x1
  return { x0: region.x0, y0: region.y0, x1, y1: region.y1 }
}

// A cubic bezier easing (like CSS cubic-bezier), so the page and the app can share one curve.
export function cubicBezier(x1, y1, x2, y2) {
  const A = (a1, a2) => 1 - 3 * a2 + 3 * a1, B = (a1, a2) => 3 * a2 - 6 * a1, C = (a1) => 3 * a1
  const bez = (t, a1, a2) => ((A(a1, a2) * t + B(a1, a2)) * t + C(a1)) * t
  const slope = (t, a1, a2) => 3 * A(a1, a2) * t * t + 2 * B(a1, a2) * t + C(a1)
  return (x) => {
    if (x <= 0) return 0
    if (x >= 1) return 1
    let t = x
    for (let i = 0; i < 8; i++) { const s = slope(t, x1, x2); if (Math.abs(s) < 1e-6) break; t -= (bez(t, x1, x2) - x) / s }
    return bez(t, y1, y2)
  }
}
export const SLIDE = cubicBezier(0.22, 1, 0.36, 1)
export const SLIDE_MS = 520

// A call-out: a hairline straight up from the part to a tiny label. `left` puts the label on the
// line's left (parts on the car's left half), otherwise on its right. `rise` is the line's length.
export function calloutLayout(anchor, { left = true, rise = 44, gap = 6 } = {}) {
  const top = anchor.y - rise
  return {
    line: [[anchor.x, anchor.y], [anchor.x, top]],
    label: { x: left ? anchor.x - gap : anchor.x + gap, y: top, align: left ? 'right' : 'left' },
  }
}
