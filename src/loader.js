// The loading screen: Milan's Jeep (his own drawing), its wheels turning slowly while the 3D model
// loads, a thin progress line under it. `progress(p)` moves the line; `done()` fades it all away.
// One module for the phone page and the CarPlay page; the look follows `currentColor`.
const CSS = `.jl{position:absolute;inset:0;display:grid;place-items:center;pointer-events:none;transition:opacity .6s ease}
.jl[data-jl=out]{opacity:0}
.jl-box{display:grid;justify-items:center;gap:18px;width:var(--jl-w,180px)}
.jl-car{position:relative;width:100%;aspect-ratio:1029/459;opacity:0;animation:jl-in .9s cubic-bezier(.22,1,.36,1) .05s both}
.jl-car img{position:absolute;display:block;-webkit-user-drag:none}
.jl-body{left:0;top:0;width:100%;height:100%}
.jl-w{width:calc(100% * 227 / 1029);height:calc(100% * 223 / 459);top:calc(100% * 234 / 459);animation:jl-turn 4.2s linear infinite}
.jl-w1{left:calc(100% * 68.5 / 1029)}
.jl-w2{left:calc(100% * 698.5 / 1029)}
.jl-line{width:60%;height:1px;position:relative}
.jl-line::before{content:"";position:absolute;inset:0;background:currentColor;opacity:.14}
.jl-line i{position:absolute;left:0;top:-0.5px;height:2px;width:0;background:currentColor;border-radius:1px;transition:width .35s cubic-bezier(.22,1,.36,1)}
[data-theme=light] .jl img{filter:invert(1)}
@keyframes jl-in{from{opacity:0;transform:translateX(-14px)}to{opacity:1;transform:none}}
@keyframes jl-turn{to{transform:rotate(360deg)}}
@media (prefers-reduced-motion:reduce){.jl-car{animation:none;opacity:1}.jl-w{animation:none}.jl-line i{transition:none}}
.jl[data-motion=still] .jl-car{animation:none;opacity:1}.jl[data-motion=still] .jl-w{animation:none}`

let injected = false

export function jeepLoader(host, { base = '' } = {}) {
  if (!injected) { injected = true; const s = document.createElement('style'); s.textContent = CSS; document.head.append(s) }
  const el = document.createElement('div')
  el.className = 'jl'
  el.setAttribute('role', 'progressbar'); el.setAttribute('aria-valuemin', '0'); el.setAttribute('aria-valuemax', '100'); el.setAttribute('aria-valuenow', '0')
  el.innerHTML = `<div class="jl-box"><div class="jl-car"><img class="jl-body" alt="" src="${base}loader/jeep-body.png"><img class="jl-w jl-w1" alt="" src="${base}loader/jeep-wheel.png"><img class="jl-w jl-w2" alt="" src="${base}loader/jeep-wheel.png"></div><div class="jl-line"><i></i></div></div>`
  host.append(el)
  const bar = el.querySelector('.jl-line i')
  let gone = false
  return {
    el,
    progress(p) {
      const v = Math.max(0, Math.min(1, p || 0))
      bar.style.width = `${(v * 100).toFixed(1)}%`
      el.setAttribute('aria-valuenow', String(Math.round(v * 100)))
    },
    /** Reduce Motion: no roll-in, still wheels. */
    still(on) { if (on) el.dataset.motion = 'still'; else delete el.dataset.motion },
    /** Fades out and removes itself (600 ms). */
    done() {
      if (gone) return
      gone = true
      bar.style.width = '100%'
      el.dataset.jl = 'out'
      setTimeout(() => el.remove(), 700)
    },
  }
}
