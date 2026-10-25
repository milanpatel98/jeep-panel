import { test } from 'node:test'
import assert from 'node:assert/strict'
import { embedCalls, shortestTurn, fitBox, boxCorners } from '../src/embedState.js'

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

test('shortestTurnWraps', () => {
  assert.equal(shortestTurn(0), 0)
  assert.equal(shortestTurn(90), 90)
  assert.equal(shortestTurn(270), -90)
  assert.equal(shortestTurn(-270), 90)
  assert.equal(shortestTurn(720 + 10), 10)
  assert.equal(shortestTurn(180), 180)
})

// projects like fitBox does, for checking it
function project(p, { az, el, ty, fovDeg, aspect }, d) {
  const rad = Math.PI / 180
  const dir = [Math.cos(el * rad) * Math.sin(az * rad), Math.sin(el * rad), Math.cos(el * rad) * Math.cos(az * rad)]
  const f = dir.map((c) => -c)
  let r = [-f[2], 0, f[0]]; const rl = Math.hypot(r[0], r[2]); r = r.map((c) => c / rl)
  const u = [r[1] * f[2] - r[2] * f[1], r[2] * f[0] - r[0] * f[2], r[0] * f[1] - r[1] * f[0]]
  const v = [p[0] - dir[0] * d, p[1] - ty - dir[1] * d, p[2] - dir[2] * d]
  const z = v[0] * f[0] + v[1] * f[1] + v[2] * f[2]
  const t = Math.tan((fovDeg * rad) / 2)
  return [(v[0] * r[0] + v[1] * r[1] + v[2] * r[2]) / (z * t * aspect), (v[0] * u[0] + v[1] * u[1] + v[2] * u[2]) / (z * t)]
}

const JEEP = boxCorners([-1.05, 0, -2.4], [1.05, 1.9, 2.4])
const HERO = { az: 38, el: 25, ty: 0.95, fovDeg: 24, aspect: 274 / 204 }
const YAWS = Array.from({ length: 24 }, (_, i) => i * 15)

test('fitBoxFillsTheFrameLessTheMargin', () => {
  const { d, cx, cy } = fitBox(JEEP, { ...HERO, margin: 0.06, yaws: YAWS })
  let x0 = Infinity, x1 = -Infinity, y0 = Infinity, y1 = -Infinity
  for (const yaw of YAWS) {
    const c = Math.cos((yaw * Math.PI) / 180), s = Math.sin((yaw * Math.PI) / 180)
    for (const [x, y, z] of JEEP) {
      const [px, py] = project([x * c + z * s, y, -x * s + z * c], HERO, d)
      x0 = Math.min(x0, px - cx); x1 = Math.max(x1, px - cx); y0 = Math.min(y0, py - cy); y1 = Math.max(y1, py - cy)
    }
  }
  // centred, inside 0.88 on both axes, and touching it on one
  assert.ok(Math.abs(x0 + x1) < 1e-6 && Math.abs(y0 + y1) < 1e-6)
  assert.ok(x1 <= 0.88 + 1e-6 && y1 <= 0.88 + 1e-6)
  assert.ok(Math.abs(Math.max(x1, y1) - 0.88) < 1e-4)
})

test('fitBoxGetsCloserForOneYawThanForAll', () => {
  const all = fitBox(JEEP, { ...HERO, margin: 0.06, yaws: YAWS })
  const one = fitBox(JEEP, { ...HERO, margin: 0.06, yaws: [0] })
  assert.ok(one.d <= all.d)
  assert.ok(fitBox(JEEP, { ...HERO, margin: 0.1, yaws: YAWS }).d > all.d)
})

test('boxCornersAreTheEight', () => {
  const c = boxCorners([0, 0, 0], [1, 2, 3])
  assert.equal(c.length, 8)
  assert.deepEqual(c[0], [0, 0, 0]); assert.deepEqual(c[7], [1, 2, 3])
})
