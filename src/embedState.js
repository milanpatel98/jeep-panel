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

// The roof strip's steps, top to bottom. The strip shows the step for a roof + doorsOff state.
export const STRIP_STEPS = [
  { key: 'on', label: 'Top on' },
  { key: 'panels', label: 'Panels' },
  { key: 'off', label: 'Top off' },
  { key: 'doorsOff', label: 'Doors off' },
]

export function stripStep(state = {}) {
  if (state.doorsOff) return 3
  const i = ROOFS.indexOf(state.roof ?? 'on')
  return i < 0 ? 0 : i
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
