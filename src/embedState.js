// What the CarPlay 3D Jeep has to do to get from one state to the next.
// Pure: returns the createJeep calls for what changed, nothing for what didn't.
// Anything prev leaves out counts as the default: lights off, roof on, doors and gate closed.
const ROOFS = ['on', 'panels', 'off']
const DOOR_KEYS = ['FL', 'FR', 'BL', 'BR']

export function embedCalls(prev = {}, next = {}) {
  const calls = []
  if (typeof next.lights === 'boolean' && next.lights !== !!prev.lights) calls.push(['setLights', next.lights])
  if (ROOFS.includes(next.roof) && next.roof !== (prev.roof ?? 'on')) calls.push(['setRoof', next.roof])
  if (next.doors) {
    for (const k of DOOR_KEYS) {
      const open = next.doors[k]
      if (typeof open === 'boolean' && open !== !!prev.doors?.[k]) calls.push(['setDoor', k, open])
    }
  }
  if (typeof next.gate === 'boolean' && next.gate !== !!prev.gate) calls.push(['setGate', next.gate])
  return calls
}
