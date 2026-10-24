// The bridge to the iPhone app.
// Native (WKWebView with a `jeep` message handler): commands go to Swift, and Swift
// pushes the truth back with window.jeepNative.apply(patch). Nothing changes here until it does.
// Browser: the same calls flip the sample state locally, like before.
import { state, set } from './state.js'

const ACTIONS = ['lock', 'unlock', 'climateOn', 'climateOff', 'lights', 'horn', 'gate']

export const isNative = () => !!globalThis.window?.webkit?.messageHandlers?.jeep

const local = {
  lock: () => set({ locked: true }),
  unlock: () => set({ locked: false }),
  climateOn: () => set({ climate: { on: true } }),
  climateOff: () => set({ climate: { on: false } }),
  lights: () => set({ lights: !state.lights }),
  gate: () => set({ gate: !state.gate }),
  horn: () => {},
}

export function request(action) {
  if (!ACTIONS.includes(action)) return
  if (isNative()) window.webkit.messageHandlers.jeep.postMessage({ type: 'command', action })
  else local[action]()
}

if (globalThis.window) window.jeepNative = { apply: (patch) => set(patch) }
if (isNative()) window.webkit.messageHandlers.jeep.postMessage({ type: 'ready' })
