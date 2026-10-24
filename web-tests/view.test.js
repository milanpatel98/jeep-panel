import { test } from 'node:test'
import assert from 'node:assert/strict'

delete globalThis.window
const view = await import('../src/view.js')

test('tiresShowAllFourCornersInPsi', () => {
  assert.equal(view.tiresText({ FL: 35, FR: 35, RL: 34, RR: 36 }), 'FL 35 · FR 35 · RL 34 · RR 36 psi')
})

test('missingTireIsDash', () => {
  assert.equal(view.tiresText({ FL: 35, FR: 35, RL: 34, RR: null }), 'FL 35 · FR 35 · RL 34 · RR — psi')
  assert.equal(view.tiresText({ FL: 35 }), 'FL 35 · FR — · RL — · RR — psi')
})

test('noTiresAtAllIsOneDash', () => {
  assert.equal(view.tiresText({ FL: null, FR: null, RL: null, RR: null }), '—')
  assert.equal(view.tiresText(undefined), '—')
})

test('dimWhenOfflineOrStale', () => {
  assert.equal(view.isDim({ offline: false, stale: false }), false)
  assert.equal(view.isDim({ offline: true, stale: false }), true)
  assert.equal(view.isDim({ offline: false, stale: true }), true)
  assert.equal(view.isDim({}), false)   // the browser never sends either
})

test('lockActionWaitsForKnownState', () => {
  assert.equal(view.lockAction(null), null)
  assert.equal(view.lockAction(undefined), null)
  assert.equal(view.lockAction(true), 'unlock')
  assert.equal(view.lockAction(false), 'lock')
})

test('chargeSubBrowserUnchanged', () => {
  const s = { battery: { pct: 84, charging: true, fullBy: '6:10 AM', added: 12 }, fuel: { miles: 312 } }
  assert.equal(view.chargeSub(s, false), 'Full by 6:10 AM · 12 mi added')
  s.battery.charging = false
  assert.equal(view.chargeSub(s, false), '84% · 312 mi on gas')
})

test('chargeSubNativeShowsFuelPercentAndOnlyRealValues', () => {
  const s = { battery: { pct: 78, charging: false, fullBy: null, added: null }, fuel: { pct: 60, miles: null } }
  assert.equal(view.chargeSub(s, true), '78% · Fuel 60%')
  s.fuel.miles = 162
  assert.equal(view.chargeSub(s, true), '78% · Fuel 60% · 162 mi on gas')
  s.fuel = { pct: null, miles: null }
  assert.equal(view.chargeSub(s, true), '78%')
  s.battery = { pct: 50, charging: true, fullBy: '2:30 PM', added: null }
  assert.equal(view.chargeSub(s, true), 'Full by 2:30 PM')   // no "— mi added"
})

test('trailsHiddenInNativeOnly', () => {
  assert.equal(view.screenFor('trails', true), 'home')
  assert.equal(view.screenFor('trails', false), 'trails')
  assert.equal(view.screenFor('controls', true), 'controls')
  assert.equal(view.screenFor('nowhere', false), 'home')
  assert.equal(view.screenFor('', true), 'home')
})
