import './style.css'
import { createJeep } from './jeep.js'
import { state, set, subscribe, isNight, attention } from './state.js'
import { I } from './icons.js'

const $ = (s, el = document) => el.querySelector(s)
const $$ = (s, el = document) => [...el.querySelectorAll(s)]
const app = $('#app'), stage = $('#stage'), sheet = $('#sheet'), tags = $('#tags')
const reduced = matchMedia('(prefers-reduced-motion: reduce)')
const wide = matchMedia('(min-width: 900px) and (orientation: landscape), (min-width: 1200px)')
const glide = () => (reduced.matches ? 1 : 900)

// ---------- static glyphs ----------
$('#i-caret').innerHTML = I.caretDown
$('#loader-glyph').innerHTML = I.jeep
$('#temp-down').innerHTML = I.caretLeft
$('#temp-up').innerHTML = I.caretLeft.replace('<svg', '<svg style="transform:scaleX(-1)"')
$$('.back').forEach((b) => (b.innerHTML = I.caretLeft))
$('#fab').innerHTML = I.caretLeft
const TILE_ICON = { doors: I.door, hood: I.carProfile, gate: I.jeep, windows: I.wind, lights: I.headlights, hazards: I.warning, horn: I.megaphone, doorsOff: I.doorOpen, lock: I.lock, power: I.power, vent: I.wind }
$$('.tile, .strip-btn').forEach((t) => (t.querySelector('i').innerHTML = TILE_ICON[t.dataset.t || t.dataset.c] || ''))
$('#map').insertAdjacentHTML('afterbegin', mapSvg())

// ---------- the car (loads in the background; the UI is live immediately) ----------
let jeep = null
const pending = []
const car = new Proxy({}, { get: (_, k) => (...a) => (jeep ? jeep[k](...a) : pending.push([k, a])) })
const loader = $('#loader'), bar = $('#bar'), pct = $('#pct')
createJeep($('#c'), {
  url: `${import.meta.env.BASE_URL}model/jeep.glb`,
  onProgress: (p) => { const v = Math.round(p * 100); bar.style.strokeDashoffset = 351.86 * (1 - p); pct.textContent = v + '%'; loader.setAttribute('aria-valuenow', v) },
  onFrame: placeTags,
}).then((j) => {
  jeep = j; window.__j = j
  bar.style.strokeDashoffset = 0; pct.textContent = '100%'
  syncCar(true)
  for (const [k, a] of pending) j[k](...a)
  j.setView(VIEW[screen()], 1)
  app.dataset.loading = '0'
  j.kick()
  mini(screen() === 'location')
}).catch((e) => { pct.textContent = 'Could not load'; console.error(e) })

// push the whole state into the engine (instant on first load, animated after)
function syncCar(instant) {
  if (!jeep) return
  for (const k of ['FL', 'FR', 'BL', 'BR']) jeep.setDoor(k, state.doors[k])
  jeep.setHood(state.hood); jeep.setGate(state.gate)
  jeep.setRoof(state.roof); jeep.setWindows(state.windows); jeep.setDoorsOff(state.doorsOff)
  jeep.setLights(state.lights); jeep.setSignal(state.hazards)
  jeep.setNight(isNight())
  if (instant) jeep.kick()
}

// ---------- screens ----------
const VIEW = { home: 'hero', controls: 'top', climate: 'top', location: 'hero', trails: 'side', about: 'rear' }
const screen = () => { const s = location.hash.replace(/^#\/?/, '') || 'home'; return VIEW[s] ? s : 'home' }
function route() {
  const s = screen()
  if (app.dataset.screen === s) return
  app.dataset.screen = s
  sheet.classList.remove('open', 'closed'); sheet.style.transform = ''
  car.setView(VIEW[s], glide())
  car.setPeek(s === 'climate')
  $('.panel[data-panel="' + s + '"]')?.scrollTo?.(0, 0)
  mini(s === 'location')
}
// the small Jeep on the map: lives only while the Location screen is open
let miniView = null
function mini(on) {
  if (on && !miniView && jeep) { miniView = jeep.miniView($('#mini-canvas')); miniView.spin(state.gear !== 'Parked' && !reduced.matches) }
  if (!on && miniView) { miniView.destroy(); miniView = null }
}
addEventListener('hashchange', route)
addEventListener('keydown', (e) => { if (e.key === 'Escape' && screen() !== 'home') location.hash = '#/' })

// ---------- sheet: three resting places (closed, peek, open) ----------
let drag = null, justDragged = false
sheet.addEventListener('click', (e) => { if (justDragged) { e.stopPropagation(); e.preventDefault() } }, true)
const snaps = () => {
  const H = sheet.clientHeight, cs = getComputedStyle(app)
  const peek = parseFloat(cs.getPropertyValue('--peek')) || 300
  const bi = parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--bottom-inset')) || 0
  return { open: 0, peek: H - peek, closed: H - 36 - bi }
}
const currentY = () => { const s = snaps(); return sheet.classList.contains('open') ? s.open : sheet.classList.contains('closed') ? s.closed : s.peek }
sheet.addEventListener('pointerdown', (e) => {
  if (wide.matches || e.button) return
  const panel = e.target.closest('.panel')
  if (e.target.closest('input, .slider')) return
  // inside an open, scrolled panel the panel scrolls; drag starts only at the top
  if (panel && sheet.classList.contains('open') && panel.scrollTop > 0) return
  drag = { y0: e.clientY, t0: performance.now(), from: currentY(), moved: false, id: e.pointerId, panel, openAtStart: sheet.classList.contains('open') }
})
addEventListener('pointermove', (e) => {
  if (!drag || e.pointerId !== drag.id) return
  const dy = e.clientY - drag.y0
  if (!drag.moved) { if (Math.abs(dy) < 6) return; if (drag.openAtStart && dy < 0) { drag = null; return } drag.moved = true; sheet.classList.add('drag'); sheet.setPointerCapture?.(drag.id) }
  const s = snaps(); const y = Math.max(s.open - 20, Math.min(s.closed + 20, drag.from + dy))
  sheet.style.transform = `translateY(${y}px)`
  e.preventDefault()
}, { passive: false })
addEventListener('pointerup', (e) => {
  if (!drag || e.pointerId !== drag.id) return
  const d = drag; drag = null
  if (!d.moved) return
  justDragged = true; setTimeout(() => (justDragged = false), 0)
  const s = snaps(); const dy = e.clientY - d.y0; const v = dy / Math.max(1, performance.now() - d.t0)   // px/ms
  let y = d.from + dy + v * 180
  const target = Object.entries(s).sort((a, b) => Math.abs(a[1] - y) - Math.abs(b[1] - y))[0][0]
  sheet.classList.remove('drag', 'open', 'closed'); sheet.style.transform = ''
  if (target !== 'peek') sheet.classList.add(target)
})
addEventListener('pointercancel', () => { if (drag) { drag = null; sheet.classList.remove('drag'); sheet.style.transform = '' } })
$('#grip').addEventListener('click', () => { if (drag?.moved) return; sheet.classList.toggle('open'); sheet.classList.remove('closed') })
sheet.addEventListener('click', (e) => { if (e.target.closest('a.row') && !wide.matches) sheet.classList.remove('open') })

// ---------- controls ----------
const toggleDoor = (k) => set({ doors: { [k]: !state.doors[k] } })
$$('.q').forEach((b) => b.addEventListener('click', () => {
  const q = b.dataset.q
  if (q === 'lock') set({ locked: !state.locked })
  if (q === 'climate') set({ climate: { on: !state.climate.on } })
  if (q === 'charge') set({ battery: { charging: !state.battery.charging } })
  if (q === 'lights') set({ lights: !state.lights })
}))
$$('.tile[data-t]').forEach((b) => b.addEventListener('click', () => {
  const t = b.dataset.t
  if (t === 'doors') { const open = !Object.values(state.doors).every(Boolean); set({ doors: { FL: open, FR: open, BL: open, BR: open } }) }
  if (t === 'hood') set({ hood: !state.hood })
  if (t === 'gate') set({ gate: !state.gate })
  if (t === 'windows') set({ windows: !state.windows })
  if (t === 'lights') set({ lights: !state.lights })
  if (t === 'hazards') set({ hazards: !state.hazards })
  if (t === 'doorsOff') set({ doorsOff: !state.doorsOff })
  if (t === 'lock') set({ locked: !state.locked })
  if (t === 'horn') { stage.classList.remove('honk'); void stage.offsetWidth; stage.classList.add('honk'); car.setBrake(true); setTimeout(() => car.setBrake(false), 300); navigator.vibrate?.(40) }
}))
$$('.seg-btn').forEach((b) => b.addEventListener('click', () => set({ roof: b.dataset.roof })))
$$('.strip-btn[data-c]').forEach((b) => b.addEventListener('click', () => {
  if (b.dataset.c === 'power') set({ climate: { on: !state.climate.on } })
  if (b.dataset.c === 'vent') set({ climate: { vent: !state.climate.vent } })
}))
$('#temp-down').addEventListener('click', () => set({ climate: { target: Math.max(60, state.climate.target - 1) } }))
$('#temp-up').addEventListener('click', () => set({ climate: { target: Math.min(82, state.climate.target + 1) } }))
$('#limit').addEventListener('input', (e) => set({ battery: { limit: +e.target.value } }))
$('#night').addEventListener('click', () => set({ night: !isNight() }))
setInterval(() => { if (state.night === null) car.setNight(isNight()), render() }, 60_000)

// tap targets and labels that ride on the car
const PARTS = ['FL', 'FR', 'BL', 'BR', 'hood', 'gate', 'roof']
const tagEls = {}, hitEls = {}
for (const p of PARTS) {
  const t = document.createElement('span'); t.className = 'tag'; tags.appendChild(t); tagEls[p] = t
  if (p === 'roof') continue
  const h = document.createElement('button'); h.className = 'hit'; h.type = 'button'
  h.setAttribute('aria-label', { FL: 'Driver door', FR: 'Passenger door', BL: 'Rear left door', BR: 'Rear right door', hood: 'Hood', gate: 'Tailgate' }[p])
  h.addEventListener('click', () => (p === 'hood' ? set({ hood: !state.hood }) : p === 'gate' ? set({ gate: !state.gate }) : toggleDoor(p)))
  tags.appendChild(h); hitEls[p] = h
}
const SEATS = ['seatFL', 'seatFR', 'seatBL', 'seatBM', 'seatBR', 'wheel']
const HEAT = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"><path d="M7.5 4c0 2.2-2.5 2.6-2.5 5s2.5 2.8 2.5 5-2.5 2.6-2.5 5"/><path d="M12.5 4c0 2.2-2.5 2.6-2.5 5s2.5 2.8 2.5 5-2.5 2.6-2.5 5"/><path d="M17.5 4c0 2.2-2.5 2.6-2.5 5s2.5 2.8 2.5 5-2.5 2.6-2.5 5"/></svg>'
const seatEls = {}
for (const k of SEATS) {
  const b = document.createElement('button'); b.className = 'seat' + (k === 'wheel' ? ' wheel' : ''); b.type = 'button'
  b.innerHTML = k === 'wheel' ? I.steering : HEAT
  b.setAttribute('aria-label', k === 'wheel' ? 'Heated steering wheel' : 'Heated seat')
  b.addEventListener('click', () => set({ heat: { [k]: !state.heat[k] } }))
  tags.appendChild(b); seatEls[k] = b
}
function placeTags() {
  if (!jeep) return
  for (const p of PARTS) {
    const a = jeep.anchor(p); if (!a) continue
    const el = tagEls[p]; const side = p === 'FL' || p === 'BL' ? -1 : p === 'FR' || p === 'BR' ? 1 : 0
    el.style.left = (a.x + side * 58) + 'px'; el.style.top = (a.y - (side || p === 'roof' ? 0 : 26)) + 'px'
    const h = hitEls[p]; if (h) { h.style.left = a.x + 'px'; h.style.top = a.y + 'px' }
  }
  for (const k of SEATS) { const a = jeep.anchor(k); if (a) { seatEls[k].style.left = a.x + 'px'; seatEls[k].style.top = a.y + 'px' } }
}

// ---------- render: state → screen ----------
const rangeEl = $('#range'), gearEl = $('#gear'), nightBtn = $('#night')
function render() {
  const b = state.battery, c = state.climate
  rangeEl.innerHTML = `<span class="batt${b.charging ? ' charging' : ''}" style="--p:${b.pct / 100}"><i></i></span>${b.miles} mi`
  const att = attention()
  gearEl.textContent = att.length ? att.join(' · ') : state.gear
  gearEl.classList.toggle('attention', att.length > 0)
  nightBtn.innerHTML = isNight() ? I.sun : I.moon
  nightBtn.setAttribute('aria-label', isNight() ? 'Day mode' : 'Night mode')

  // quick controls
  const q = (k) => $(`.q[data-q="${k}"]`)
  q('lock').innerHTML = state.locked ? I.lock : I.lockOpen; q('lock').classList.toggle('on', !state.locked)
  q('climate').innerHTML = I.fan; q('climate').classList.toggle('on', c.on)
  q('charge').innerHTML = I.lightning; q('charge').classList.toggle('on', b.charging)
  q('lights').innerHTML = I.headlights; q('lights').classList.toggle('on', state.lights)

  // charging
  $('#charge').classList.toggle('charging', b.charging)
  $('#charge-title').textContent = `Charge limit ${b.limit}%`
  $('#charge-state').textContent = b.charging ? 'Charging' : b.pct >= b.limit ? 'Charged' : 'Not charging'
  $('#charge-sub').textContent = b.charging ? `Full by ${b.fullBy} · ${b.added} mi added` : `${b.pct}% · ${state.fuel.miles} mi on gas`
  const lim = $('#limit'); if (+lim.value !== b.limit) lim.value = b.limit
  lim.style.setProperty('--fill', ((b.limit - 50) / 50) * 100 + '%')

  // rows
  const rc = $('#row-controls'); rc.textContent = att.filter((s) => !/Unlocked|Lights|Hazards/.test(s)).join(' · ') || (state.locked ? 'Locked' : 'Unlocked'); rc.classList.toggle('attention', /open/.test(rc.textContent))
  $('#row-climate').textContent = (c.on ? `On · ${c.target.toFixed(0)}° · ` : '') + `Interior ${c.interior}°`
  $('#row-location').textContent = state.location.label
  $('#row-trails').textContent = `Last: ${state.trail.name}, ${state.trail.miles} mi`
  $('#odo').textContent = state.odometer.toLocaleString() + ' mi'

  // tiles
  const allDoors = Object.values(state.doors).every(Boolean), anyDoor = Object.values(state.doors).some(Boolean)
  const tile = (k) => $(`.tile[data-t="${k}"]`)
  tile('doors').classList.toggle('open', anyDoor); tile('doors').querySelector('span').textContent = allDoors ? 'Close doors' : anyDoor ? 'Doors open' : 'Doors'
  tile('hood').classList.toggle('open', state.hood); tile('hood').querySelector('span').textContent = state.hood ? 'Hood open' : 'Hood'
  tile('gate').classList.toggle('open', state.gate); tile('gate').querySelector('span').textContent = state.gate ? 'Tailgate open' : 'Tailgate'
  tile('windows').classList.toggle('on', state.windows); tile('windows').querySelector('span').textContent = state.windows ? 'Windows down' : 'Windows'
  tile('lights').classList.toggle('on', state.lights)
  tile('hazards').classList.toggle('on', state.hazards)
  tile('doorsOff').classList.toggle('on', state.doorsOff)
  tile('lock').classList.toggle('open', !state.locked); tile('lock').querySelector('i').innerHTML = state.locked ? I.lock : I.lockOpen; tile('lock').querySelector('span').textContent = state.locked ? 'Locked' : 'Unlocked'
  $$('.seg-btn').forEach((s) => s.setAttribute('aria-checked', s.dataset.roof === state.roof))

  // climate
  $('#temp').textContent = c.target.toFixed(0)
  $('#climate-sub').textContent = `Interior ${c.interior}°F · Exterior ${c.exterior}°F`
  const pw = $('.strip-btn[data-c="power"]'); pw.classList.toggle('on', c.on); pw.querySelector('span').textContent = c.on ? 'On' : 'Off'
  $('.strip-btn[data-c="vent"]').classList.toggle('on', c.vent)
  for (const k of SEATS) seatEls[k].classList.toggle('on', !!state.heat[k])

  // location
  $('#place').textContent = state.location.label
  $('#place-sub').textContent = `${state.location.detail} · Parked ${state.location.since}`
  $('#mini-label').textContent = `${state.location.label} · ${state.gear === 'Parked' ? 'Parked ' + state.location.since : state.gear}`

  // labels on the car
  for (const k of ['FL', 'FR', 'BL', 'BR']) { tagEls[k].innerHTML = `${I.doorOpen}Open`; tagEls[k].classList.toggle('show', state.doors[k] && !state.doorsOff); hitEls[k].classList.toggle('on', state.doors[k]) }
  tagEls.hood.innerHTML = `${I.carProfile}Open`; tagEls.hood.classList.toggle('show', state.hood); hitEls.hood.classList.toggle('on', state.hood)
  tagEls.gate.innerHTML = `${I.jeep}Open`; tagEls.gate.classList.toggle('show', state.gate); hitEls.gate.classList.toggle('on', state.gate)
  tagEls.roof.className = 'tag quiet' + (state.roof !== 'on' ? ' show' : ''); tagEls.roof.textContent = state.roof === 'panels' ? 'Panels off' : 'Top off'
}

subscribe((s, patch) => {
  render()
  if ('gear' in patch) miniView?.spin(s.gear !== 'Parked' && !reduced.matches)
  if (!jeep) return
  if (patch.doors) for (const k of Object.keys(patch.doors)) jeep.setDoor(k, s.doors[k])
  if ('hood' in patch) jeep.setHood(s.hood)
  if ('gate' in patch) jeep.setGate(s.gate)
  if ('roof' in patch) jeep.setRoof(s.roof)
  if ('windows' in patch) jeep.setWindows(s.windows)
  if ('doorsOff' in patch) jeep.setDoorsOff(s.doorsOff)
  if ('lights' in patch) jeep.setLights(s.lights)
  if ('hazards' in patch) jeep.setSignal(s.hazards)
  if ('night' in patch) jeep.setNight(isNight())
})

function mapSvg() {
  // a few quiet streets around home; not a real map
  return `<svg viewBox="0 0 360 180" preserveAspectRatio="xMidYMid slice" aria-hidden="true">
    <g stroke="#36373b" stroke-width="10" stroke-linecap="round" fill="none">
      <path d="M-10 62 H370" /><path d="M-10 128 H370" /><path d="M96 -10 V190" /><path d="M250 -10 V190" />
    </g>
    <g stroke="#2f3034" stroke-width="5" stroke-linecap="round" fill="none">
      <path d="M-10 96 H370" /><path d="M172 -10 V190" /><path d="M312 -10 V190" /><path d="M40 -10 V190" />
      <path d="M250 62 Q 300 40 370 20" />
    </g>
    <circle cx="180" cy="100" r="30" fill="rgba(255,255,255,0.04)" />
  </svg>`
}

// ---------- go ----------
route(); render()
addEventListener('resize', () => { sheet.style.transform = ''; if (!wide.matches) return; sheet.classList.remove('open', 'closed') })
