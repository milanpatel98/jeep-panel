// One place for everything the app knows about the car.
// Sample data for now; a real feed replaces `set()` calls with its own, the UI does not change.

const listeners = new Set()

export const state = {
  name: 'Wrangler',
  gear: 'Parked',
  locked: true,
  // battery (4xe: ~21 mi electric)
  battery: { pct: 84, miles: 18, limit: 80, charging: true, fullBy: '6:10 AM', added: 12 },
  fuel: { miles: 312 },
  climate: { on: false, target: 70, interior: 68, exterior: 54, vent: false },
  heat: { seatFL: false, seatFR: false, seatBL: false, seatBM: false, seatBR: false, wheel: false },
  lights: false,
  hazards: false,
  doors: { FL: false, FR: false, BL: false, BR: false },
  doorsOff: false,
  hood: false,
  gate: false,
  roof: 'on',          // 'on' | 'panels' | 'off'
  windows: false,      // true = down
  location: { label: 'Home', detail: 'Golden, CO', since: '2h', lat: 39.7555, lng: -105.2211, heading: 35 },
  trail: { name: 'Guanella Pass', miles: 42 },
  odometer: 14_212,
  night: null,         // null = follow the clock
}

export function set(patch) {
  for (const [k, v] of Object.entries(patch)) {
    state[k] = v && typeof v === 'object' && !Array.isArray(v) && state[k] && typeof state[k] === 'object' ? { ...state[k], ...v } : v
  }
  for (const fn of listeners) fn(state, patch)
}

export function subscribe(fn) { listeners.add(fn); return () => listeners.delete(fn) }

export const isNight = () => {
  if (state.night !== null) return state.night
  const h = new Date().getHours() + new Date().getMinutes() / 60
  return h < 6.5 || h >= 19
}

// what deserves attention right now (shown in amber)
export function attention() {
  const open = Object.entries(state.doors).filter(([, v]) => v).map(([k]) => k)
  const parts = []
  if (open.length === 4) parts.push('All doors open')
  else if (open.length) parts.push(open.map((k) => ({ FL: 'Driver door', FR: 'Passenger door', BL: 'Rear left door', BR: 'Rear right door' })[k]).join(', ') + ' open')
  if (state.hood) parts.push('Hood open')
  if (state.gate) parts.push('Tailgate open')
  if (state.lights) parts.push('Lights on')
  if (state.hazards) parts.push('Hazards on')
  if (!state.locked) parts.push('Unlocked')
  return parts
}
