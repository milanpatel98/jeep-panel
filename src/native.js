// The bridge to the iPhone app.
// Native (WKWebView with a `jeep` message handler): commands go to Swift, and Swift
// pushes the truth back with window.jeepNative.apply(patch). Nothing changes here until it does.
// Browser: the same calls flip the sample state locally, like before.
//
// Contract (Swift side must match):
//   web → Swift: {type:"ready"} on load; {type:"command", action} with action one of ACTIONS.
//   Swift → web: window.jeepNative.apply(patch); patch keys are the `state` keys plus
//     pending:   {lock?, climate?, lights?, horn?, gate?: bool}  ring on the button; taps ignored
//     supported: string[] of "lock"|"climate"|"lights"|"horn"|"gate"  others are hidden
//     updated:   string, e.g. "Updated 3 min ago"
//     offline:   bool  dims the stats
//     message:   string|null  shown in the status line for 4 s ...
//     messageId: number  ... each time messageId changes (same text with a new id shows again;
//                a patch that repeats the old id does not restart the 4 s)
import { state, set, subscribe } from './state.js'

const ACTIONS = ['lock', 'unlock', 'climateOn', 'climateOff', 'lights', 'horn', 'gate']
const PENDING_KEY = { lock: 'lock', unlock: 'lock', climateOn: 'climate', climateOff: 'climate', lights: 'lights', horn: 'horn', gate: 'gate' }
const MESSAGE_MS = 4000

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
  if (state.pending?.[PENDING_KEY[action]]) return   // the Jeep is still working on it: one tap, one command
  if (isNative()) window.webkit.messageHandlers.jeep.postMessage({ type: 'command', action })
  else local[action]()
}

// the status-line message: visible for 4 s from each new messageId
let messageUntil = 0, lastMessageId = state.messageId
subscribe((s, patch) => {
  if (!('messageId' in patch) || patch.messageId === lastMessageId) return
  lastMessageId = patch.messageId
  messageUntil = Date.now() + MESSAGE_MS
  setTimeout(() => set({}), MESSAGE_MS)   // redraw when it runs out
})
export const visibleMessage = () => (state.message && Date.now() < messageUntil ? state.message : null)

if (globalThis.window) window.jeepNative = { apply: (patch) => set(patch) }
if (isNative()) window.webkit.messageHandlers.jeep.postMessage({ type: 'ready' })
