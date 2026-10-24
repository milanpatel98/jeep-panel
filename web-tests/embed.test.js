import { test } from 'node:test'
import assert from 'node:assert/strict'
import { embedCalls } from '../src/embedState.js'

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
