import { test } from 'node:test'
import assert from 'node:assert/strict'

// state.js decides native vs browser when it is imported, so every test
// loads a fresh copy (the query string makes node treat it as a new module).
let n = 0
const fresh = () => import(`../src/state.js?t=${++n}`)
const fakeNative = () => { globalThis.window = { webkit: { messageHandlers: { jeep: { postMessage() {} } } } } }

test('nativeDefaultsAreOff', async () => {
  fakeNative()
  try {
    const { state } = await fresh()
    assert.equal(state.locked, null)
    assert.equal(state.lights, false)
    assert.equal(state.climate.on, false)
    assert.equal(state.name, 'Milan')
    assert.equal(state.battery.pct, null)
    assert.equal(state.battery.miles, null)
    assert.deepEqual(state.fuel, { pct: null, miles: null })
    assert.deepEqual(state.tires, { FL: null, FR: null, RL: null, RR: null })
    assert.equal(state.stale, false)
    assert.equal(state.odometer, null)
    assert.deepEqual(state.supported, [])
    assert.deepEqual(state.pending, { lock: false, climate: false, lights: false, horn: false, gate: false })
    assert.equal(state.offline, false)
    assert.equal(state.message, null)
    assert.equal(state.updated, '')
  } finally { delete globalThis.window }
})

test('nativeDoesNotShowSampleGearLocationTrail', async () => {
  fakeNative()
  try {
    const { state } = await fresh()
    assert.equal(state.gear, null)
    assert.deepEqual(state.location, { label: null, detail: null, since: null, lat: null, lng: null, heading: null })
    assert.deepEqual(state.trail, { name: null, miles: null })
    assert.equal(state.messageId, 0)
  } finally { delete globalThis.window }
})

test('browserDefaultsUnchanged', async () => {
  delete globalThis.window
  const { state } = await fresh()
  assert.equal(state.name, 'Wrangler')
  assert.equal(state.locked, true)
  assert.equal(state.lights, false)
  assert.deepEqual(state.battery, { pct: 84, miles: 18, limit: 80, charging: true, fullBy: '6:10 AM', added: 12 })
  assert.deepEqual(state.fuel, { miles: 312 })
  assert.deepEqual(state.climate, { on: false, target: 70, interior: 68, exterior: 54, vent: false })
  assert.equal(state.odometer, 14_212)
  assert.equal(state.gear, 'Parked')
  assert.deepEqual(state.location, { label: 'Home', detail: 'Golden, CO', since: '2h', lat: 39.7555, lng: -105.2211, heading: 35 })
  assert.equal(state.trail.name, 'Guanella Pass')
  assert.equal(state.tires, undefined)   // no tires row in the browser
  assert.equal(state.stale, false)
})

test('attentionDoesNotCallUnknownLockUnlocked', async () => {
  fakeNative()
  try {
    const { attention } = await fresh()
    assert.ok(!attention().includes('Unlocked'))
  } finally { delete globalThis.window }
})
