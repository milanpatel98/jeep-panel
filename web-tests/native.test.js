import { test, mock } from 'node:test'
import assert from 'node:assert/strict'

// a fake WKWebView message handler, installed before anything is imported
const posted = []
globalThis.window = { webkit: { messageHandlers: { jeep: { postMessage: (m) => posted.push(m) } } } }

const native = await import('../src/native.js')
const stateModule = await import('../src/state.js')
const { state } = stateModule

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

test('settingsTapPostsSettings', () => {
  posted.length = 0
  assert.equal(native.openSettings(), true)
  assert.deepEqual(posted, [{ type: 'settings' }])
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

test('tapWhilePendingPostsNothing', () => {
  window.jeepNative.apply({ pending: { lock: true }, supported: ['lock'] })
  posted.length = 0
  native.request('lock')
  native.request('unlock')
  assert.deepEqual(posted, [])
  window.jeepNative.apply({ pending: { lock: false } })
  native.request('lock')
  assert.deepEqual(posted, [{ type: 'command', action: 'lock' }])
})

test('sameMessageShowsAgainWhenMessageIdChanges', () => {
  mock.timers.enable({ apis: ['Date', 'setTimeout'], now: 1_000_000 })
  try {
    const text = 'Jeep didn\'t answer. Try again.'
    window.jeepNative.apply({ message: text, messageId: 1 })
    assert.equal(native.visibleMessage(), text)
    mock.timers.tick(4001)
    assert.equal(native.visibleMessage(), null)
    // Swift resends the full patch: same text, same id → stays hidden
    window.jeepNative.apply({ message: text, messageId: 1 })
    assert.equal(native.visibleMessage(), null)
    // the same text again as a new message → shown again for 4 s
    window.jeepNative.apply({ message: text, messageId: 2 })
    assert.equal(native.visibleMessage(), text)
    mock.timers.tick(3999)
    assert.equal(native.visibleMessage(), text)
    mock.timers.tick(2)
    assert.equal(native.visibleMessage(), null)
  } finally { mock.timers.reset() }
})

test('messageExpiryRedraws', () => {
  mock.timers.enable({ apis: ['Date', 'setTimeout'], now: 2_000_000 })
  try {
    window.jeepNative.apply({ message: 'Hi', messageId: 3 })
    let redraws = 0
    const off = stateModule.subscribe(() => redraws++)
    mock.timers.tick(4001)
    off()
    assert.ok(redraws >= 1)
  } finally { mock.timers.reset() }
})
