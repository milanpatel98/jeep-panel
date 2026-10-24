import { test } from 'node:test'
import assert from 'node:assert/strict'

// no window.webkit: plain browser, request() falls back to local toggles
delete globalThis.window
const native = await import('../src/native.js')
const { state } = await import('../src/state.js')

test('browserIsNotNative', () => {
  assert.equal(native.isNative(), false)
})

test('browserRequestTogglesLocally', () => {
  native.request('unlock'); assert.equal(state.locked, false)
  native.request('lock'); assert.equal(state.locked, true)
  native.request('climateOn'); assert.equal(state.climate.on, true)
  native.request('climateOff'); assert.equal(state.climate.on, false)
  native.request('lights'); assert.equal(state.lights, true)
  native.request('lights'); assert.equal(state.lights, false)
  native.request('gate'); assert.equal(state.gate, true)
  native.request('gate'); assert.equal(state.gate, false)
  assert.doesNotThrow(() => native.request('horn'))
})
