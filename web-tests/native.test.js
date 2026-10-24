import { test } from 'node:test'
import assert from 'node:assert/strict'

// a fake WKWebView message handler, installed before anything is imported
const posted = []
globalThis.window = { webkit: { messageHandlers: { jeep: { postMessage: (m) => posted.push(m) } } } }

const native = await import('../src/native.js')
const { state } = await import('../src/state.js')

test('readyPostedOnLoad', () => {
  assert.deepEqual(posted[0], { type: 'ready' })
})

test('isNativeWhenHandlerExists', () => {
  assert.equal(native.isNative(), true)
})

test('requestPostsCommand', () => {
  posted.length = 0
  native.request('lock')
  assert.deepEqual(posted, [{ type: 'command', action: 'lock' }])
})

test('requestDoesNotChangeStateWhenNative', () => {
  posted.length = 0
  native.request('unlock')
  assert.equal(state.locked, null)
  assert.deepEqual(posted, [{ type: 'command', action: 'unlock' }])
})

test('requestIgnoresUnknownAction', () => {
  posted.length = 0
  native.request('selfDestruct')
  assert.deepEqual(posted, [])
})

test('applyPatchesState', () => {
  window.jeepNative.apply({ pending: { lock: true } })
  assert.equal(state.pending.lock, true)
  assert.equal(state.pending.climate, false)
  window.jeepNative.apply({ supported: ['horn', 'lock'], locked: false, offline: true, message: 'Jeep didn\'t answer. Try again.', updated: 'Updated 3 min ago' })
  assert.deepEqual(state.supported, ['horn', 'lock'])
  assert.equal(state.locked, false)
  assert.equal(state.offline, true)
  assert.equal(state.message, 'Jeep didn\'t answer. Try again.')
  assert.equal(state.updated, 'Updated 3 min ago')
})
