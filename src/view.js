// Small pure helpers for render() in main.js (no DOM, so web-tests can check them).

export const dash = (v, unit = '') => (v == null ? '—' : v + unit)

// which camera view each screen uses; also the list of screens
export const VIEW = { home: 'hero', controls: 'top', climate: 'top', location: 'hero', trails: 'side', about: 'rear' }
// the iPhone app has no trail data: no Trails screen there
const NATIVE_HIDDEN = new Set(['trails'])

export function screenFor(name, native) {
  const s = name || 'home'
  return VIEW[s] && !(native && NATIVE_HIDDEN.has(s)) ? s : 'home'
}

// "FL 35 · FR 35 · RL 34 · RR — psi"; one "—" when nothing is known
const CORNERS = ['FL', 'FR', 'RL', 'RR']
export function tiresText(tires) {
  const t = tires || {}
  if (CORNERS.every((k) => t[k] == null)) return '—'
  return CORNERS.map((k) => `${k} ${dash(t[k])}`).join(' · ') + ' psi'
}

// stats are dimmed while offline or when the data is older than 10 min (Swift decides `stale`)
export const isDim = (s) => !!(s.offline || s.stale)

// the lock control does nothing until the lock state is known
export const lockAction = (locked) => (locked == null ? null : locked ? 'unlock' : 'lock')

// the line under the charge card; the iPhone app shows only values the Jeep sent
export function chargeSub(s, native) {
  const b = s.battery || {}, f = s.fuel || {}
  if (!native) return b.charging ? `Full by ${dash(b.fullBy)} · ${dash(b.added, ' mi')} added` : `${dash(b.pct, '%')} · ${dash(f.miles, ' mi')} on gas`
  if (b.charging) return `Full by ${dash(b.fullBy)}`
  return [dash(b.pct, '%'), f.pct != null ? `Fuel ${f.pct}%` : null, f.miles != null ? `${f.miles} mi on gas` : null].filter((v) => v != null).join(' · ')
}
