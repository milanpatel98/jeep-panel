import { test } from 'node:test'
import assert from 'node:assert/strict'
import { embedCalls, stripStep, shortestTurn, fitDistance } from '../src/embedState.js'

test('embedCallsOnlyDiffs', () => {
  assert.deepEqual(embedCalls({}, { lights: true }), [['setLights', true]])
  assert.deepEqual(embedCalls({ lights: true }, { lights: true }), [])
  // locked and reducedMotion change nothing on the 3D Jeep
  assert.deepEqual(embedCalls({ lights: false }, { locked: true, reducedMotion: true }), [])
})

test('embedCallsRoof', () => {
  assert.deepEqual(embedCalls({ roof: 'on' }, { roof: 'panels' }), [['setRoof', 'panels']])
  assert.deepEqual(embedCalls({ roof: 'panels' }, { roof: 'off' }), [['setRoof', 'off']])
  assert.deepEqual(embedCalls({ roof: 'off' }, { roof: 'off' }), [])
})

test('embedCallsDoors', () => {
  const closed = { FL: false, FR: false, BL: false, BR: false }
  assert.deepEqual(
    embedCalls({ doors: closed }, { doors: { FL: true, FR: false, BL: true, BR: false } }),
    [['setDoor', 'FL', true], ['setDoor', 'BL', true]],
  )
  // a partial doors object only touches the doors it names
  assert.deepEqual(embedCalls({ doors: { ...closed, FR: true } }, { doors: { FR: false } }), [['setDoor', 'FR', false]])
  assert.deepEqual(embedCalls({ gate: false }, { gate: true }), [['setGate', true]])
})

test('embedCallsTheme', () => {
  assert.deepEqual(embedCalls({ theme: 'dark' }, { theme: 'light' }), [['setTheme', 'light']])
  assert.deepEqual(embedCalls({ theme: 'light' }, { theme: 'dark' }), [['setTheme', 'dark']])
  assert.deepEqual(embedCalls({ theme: 'light' }, { theme: 'light' }), [])
  // dark is the default; unknown themes are ignored
  assert.deepEqual(embedCalls({}, { theme: 'dark' }), [])
  assert.deepEqual(embedCalls({}, { theme: 'sepia' }), [])
})

test('embedCallsDoorsOff', () => {
  assert.deepEqual(embedCalls({}, { doorsOff: true }), [['setDoorsOff', true]])
  assert.deepEqual(embedCalls({ doorsOff: true }, { doorsOff: false }), [['setDoorsOff', false]])
  assert.deepEqual(embedCalls({ doorsOff: false }, { doorsOff: false }), [])
  // roof and doors-off together: roof first
  assert.deepEqual(embedCalls({ roof: 'on' }, { roof: 'off', doorsOff: true }), [['setRoof', 'off'], ['setDoorsOff', true]])
})

test('stripStepFollowsRoofAndDoors', () => {
  assert.equal(stripStep({}), 0)
  assert.equal(stripStep({ roof: 'on' }), 0)
  assert.equal(stripStep({ roof: 'panels' }), 1)
  assert.equal(stripStep({ roof: 'off' }), 2)
  assert.equal(stripStep({ roof: 'off', doorsOff: true }), 3)
  assert.equal(stripStep({ roof: 'bogus' }), 0)
})

test('shortestTurnWraps', () => {
  assert.equal(shortestTurn(0), 0)
  assert.equal(shortestTurn(90), 90)
  assert.equal(shortestTurn(270), -90)
  assert.equal(shortestTurn(-270), 90)
  assert.equal(shortestTurn(720 + 10), 10)
  assert.equal(shortestTurn(180), 180)
})

test('fitDistanceFitsTheSphere', () => {
  // the sphere's silhouette, seen from fitDistance, takes exactly (1 - 2·margin) of the narrower side
  for (const [r, fov, aspect, m] of [[2.8, 24, 1.34, 0.08], [1, 40, 0.5, 0], [3, 24, 2, 0.1]]) {
    const d = fitDistance(r, fov, aspect, m)
    const half = Math.asin(r / d)                       // silhouette half-angle
    const tanV = Math.tan((fov * Math.PI) / 360)
    const used = Math.tan(half) / Math.min(tanV, tanV * aspect)
    assert.ok(Math.abs(used - (1 - 2 * m)) < 1e-9, `${used}`)
  }
})

test('fitDistanceGrowsWithRadiusAndMargin', () => {
  assert.ok(fitDistance(3, 24, 1.3, 0.08) > fitDistance(2, 24, 1.3, 0.08))
  assert.ok(fitDistance(2, 24, 1.3, 0.12) > fitDistance(2, 24, 1.3, 0.08))
  // a narrow area: the width limits, so a narrower one needs more distance
  assert.ok(fitDistance(2, 24, 0.6, 0.08) > fitDistance(2, 24, 0.8, 0.08))
  // a wide area: the height limits, extra width changes nothing
  assert.equal(fitDistance(2, 24, 2, 0.08), fitDistance(2, 24, 3, 0.08))
  assert.equal(fitDistance(0, 24, 1, 0.08), 0)
})
