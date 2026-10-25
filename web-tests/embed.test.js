import { test } from 'node:test'
import assert from 'node:assert/strict'
import { embedCalls, stripStep, shortestTurn } from '../src/embedState.js'

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
