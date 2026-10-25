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

// How far a perspective camera must stand from a sphere's centre so the whole sphere fits the frame
// with `margin` (a fraction of the frame) left free on every side. `fovDeg` is the vertical field of
// view; `aspect` is width / height of the area the sphere has to fit in. The sphere's silhouette is a
// cone of half-angle asin(r / d), so it fits when that is within the narrower half-angle.
export function fitDistance(radius, fovDeg, aspect, margin = 0) {
  if (!(radius > 0) || !(fovDeg > 0) || !(aspect > 0)) return 0
  const tan = Math.tan((fovDeg * Math.PI) / 360) * (1 - 2 * Math.min(Math.max(margin, 0), 0.45))
  const t = Math.min(tan, tan * aspect)
  return (radius * Math.sqrt(1 + t * t)) / t
}
