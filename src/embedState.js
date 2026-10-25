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
