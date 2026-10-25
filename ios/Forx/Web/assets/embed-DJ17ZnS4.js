import{M as B,P as me,C as k,a as he,V as M,W as pe,H as ge,S as ve,U as we,b as K,c as $,d as ye,B as Q,e as Z,f as xe,O as ee,g as te,h as be,D as Me,i as Se,j as Fe,k as Oe,l as j,m as ke,n as Re,o as Ce,p as Pe,q as _e,r as De}from"./jeep-DygOFAKD.js";class z extends B{constructor(t,r={}){super(t),this.isReflector=!0,this.type="Reflector",this.camera=new me;const a=this,n=r.color!==void 0?new k(r.color):new k(8355711),f=r.textureWidth||512,x=r.textureHeight||512,h=r.clipBias||0,u=r.shader||z.ReflectorShader,C=r.multisample!==void 0?r.multisample:4,p=new he,m=new M,i=new M,P=new M,v=new K,F=new M(0,0,-1),d=new $,b=new M,w=new M,o=new $,s=new K,l=this.camera,_=new pe(f,x,{samples:C,type:ge}),O=new ve({name:u.name!==void 0?u.name:"unspecified",uniforms:we.clone(u.uniforms),fragmentShader:u.fragmentShader,vertexShader:u.vertexShader});O.uniforms.tDiffuse.value=_.texture,O.uniforms.color.value=n,O.uniforms.textureMatrix.value=s,this.material=O,this.onBeforeRender=function(c,E,T){if(i.setFromMatrixPosition(a.matrixWorld),P.setFromMatrixPosition(T.matrixWorld),v.extractRotation(a.matrixWorld),m.set(0,0,1),m.applyMatrix4(v),b.subVectors(i,P),b.dot(m)>0)return;b.reflect(m).negate(),b.add(i),v.extractRotation(T.matrixWorld),F.set(0,0,-1),F.applyMatrix4(v),F.add(P),w.subVectors(i,F),w.reflect(m).negate(),w.add(i),l.position.copy(b),l.up.set(0,1,0),l.up.applyMatrix4(v),l.up.reflect(m),l.lookAt(w),l.far=T.far,l.updateMatrixWorld(),l.projectionMatrix.copy(T.projectionMatrix),s.set(.5,0,0,.5,0,.5,0,.5,0,0,.5,.5,0,0,0,1),s.multiply(l.projectionMatrix),s.multiply(l.matrixWorldInverse),s.multiply(a.matrixWorld),p.setFromNormalAndCoplanarPoint(m,i),p.applyMatrix4(l.matrixWorldInverse),d.set(p.normal.x,p.normal.y,p.normal.z,p.constant);const g=l.projectionMatrix;o.x=(Math.sign(d.x)+g.elements[8])/g.elements[0],o.y=(Math.sign(d.y)+g.elements[9])/g.elements[5],o.z=-1,o.w=(1+g.elements[10])/g.elements[14],d.multiplyScalar(2/d.dot(o)),g.elements[2]=d.x,g.elements[6]=d.y,g.elements[10]=d.z+1-h,g.elements[14]=d.w,a.visible=!1;const de=c.getRenderTarget(),fe=c.xr.enabled,ue=c.shadowMap.autoUpdate;c.xr.enabled=!1,c.shadowMap.autoUpdate=!1,c.setRenderTarget(_),c.state.buffers.depth.setMask(!0),c.autoClear===!1&&c.clear(),c.render(E,l),c.xr.enabled=fe,c.shadowMap.autoUpdate=ue,c.setRenderTarget(de);const J=T.viewport;J!==void 0&&c.state.viewport(J),a.visible=!0},this.getRenderTarget=function(){return _},this.dispose=function(){_.dispose(),a.material.dispose()}}}z.ReflectorShader={name:"ReflectorShader",uniforms:{color:{value:null},tDiffuse:{value:null},textureMatrix:{value:null}},vertexShader:`
		uniform mat4 textureMatrix;
		varying vec4 vUv;

		#include <common>
		#include <logdepthbuf_pars_vertex>

		void main() {

			vUv = textureMatrix * vec4( position, 1.0 );

			gl_Position = projectionMatrix * modelViewMatrix * vec4( position, 1.0 );

			#include <logdepthbuf_vertex>

		}`,fragmentShader:`
		uniform vec3 color;
		uniform sampler2D tDiffuse;
		varying vec4 vUv;

		#include <logdepthbuf_pars_fragment>

		float blendOverlay( float base, float blend ) {

			return( base < 0.5 ? ( 2.0 * base * blend ) : ( 1.0 - 2.0 * ( 1.0 - base ) * ( 1.0 - blend ) ) );

		}

		vec3 blendOverlay( vec3 base, vec3 blend ) {

			return vec3( blendOverlay( base.r, blend.r ), blendOverlay( base.g, blend.g ), blendOverlay( base.b, blend.b ) );

		}

		void main() {

			#include <logdepthbuf_fragment>

			vec4 base = texture2DProj( tDiffuse, vUv );
			gl_FragColor = vec4( blendOverlay( base.rgb, color ), 1.0 );

			#include <tonemapping_fragment>
			#include <colorspace_fragment>

		}`};const ne=["on","panels","off"],Te=["FL","FR","BL","BR"],Be=["dark","light"];function Ee(e={},t={}){const r=[];if(Be.includes(t.theme)&&t.theme!==(e.theme??"dark")&&r.push(["setTheme",t.theme]),typeof t.lights=="boolean"&&t.lights!==!!e.lights&&r.push(["setLights",t.lights]),ne.includes(t.roof)&&t.roof!==(e.roof??"on")&&r.push(["setRoof",t.roof]),typeof t.doorsOff=="boolean"&&t.doorsOff!==!!e.doorsOff&&r.push(["setDoorsOff",t.doorsOff]),t.doors)for(const a of Te){const n=t.doors[a];typeof n=="boolean"&&n!==!!e.doors?.[a]&&r.push(["setDoor",a,n])}return typeof t.gate=="boolean"&&t.gate!==!!e.gate&&r.push(["setGate",t.gate]),r}const oe=[{key:"on",label:"Top on"},{key:"panels",label:"Panels"},{key:"off",label:"Top off"},{key:"doorsOff",label:"Doors off"}];function se(e={}){if(e.doorsOff)return 3;const t=ne.indexOf(e.roof??"on");return t<0?0:t}function Ue(e){let t=e%360;return t>180&&(t-=360),t<=-180&&(t+=360),t}const U=document.getElementById("c"),I=new URLSearchParams(location.search),G=e=>window.webkit?.messageHandlers?.jeep?.postMessage(e),je={theme:"dark",lights:!1,roof:"on",doorsOff:!1,doors:{FL:!1,FR:!1,BL:!1,BR:!1},gate:!1};let D=structuredClone(je),y={},S=null,R=!!window.matchMedia?.("(prefers-reduced-motion: reduce)").matches,ie=0,N=!1;const L=(e,t)=>({...e,...t,...t.doors?{doors:{...e.doors,...t.doors}}:{}});function q(){clearTimeout(ie),!(N||!S)&&(N=!0,S.setView("hero",R?1:1600))}function le(){const e=y.theme==="light"?"light":"dark";if(document.documentElement.dataset.theme=e,Y||V(se(L(D,y)),!1),!!S){for(const[t,...r]of Ee(D,y))S[t](...r);D=L(D,y)}}const Le=e=>e<.5?4*e*e*e:1-Math.pow(-2*e+2,3)/2;let H=0,W=0,ce=0;function A(e){H=e,S&&(S.root.rotation.y=_e.degToRad(e),S.kick())}function X(){cancelAnimationFrame(W),W=0,clearTimeout(ce)}function We(){X();const e=Ue(H);if(R||Math.abs(e)<.05){A(0);return}const t=performance.now(),r=a=>{const n=Math.min(1,(a-t)/900);A(e*(1-Le(n))),W=n<1?requestAnimationFrame(r):0};W=requestAnimationFrame(r)}const re=document.getElementById("strip"),Ae=document.getElementById("puck"),Ve=document.getElementById("strip-label"),ze=['<rect x="7" y="13" width="18" height="26" rx="3" fill="currentColor" opacity=".9"/>','<rect x="7" y="23" width="18" height="16" rx="3" fill="currentColor" opacity=".9"/>',"",""],He='<rect x="3" y="2" width="26" height="52" rx="9" fill="none" stroke="currentColor" stroke-width="2"/>',Ie='<path d="M3 17V11a9 9 0 0 1 9-9h8a9 9 0 0 1 9 9v6M3 41v4a9 9 0 0 0 9 9h8a9 9 0 0 0 9-9v-4" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>',Ge=e=>`<svg viewBox="0 0 32 56" aria-hidden="true">${e===3?Ie:He}${ze[e]}<path d="M8 8h16" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>`;let ae=-1,Y=!1;function V(e,t){const r=oe.length-1,a=Math.round(Math.min(r,Math.max(0,e)));re.classList.toggle("live",t),re.style.setProperty("--pos",String(e/r)),a!==ae&&(ae=a,Ae.innerHTML=Ge(a),Ve.textContent=oe[a].label)}window.jeepEmbed={apply(e={}){y=L(y,e),typeof e.reducedMotion=="boolean"&&(R=e.reducedMotion||R,document.documentElement.classList.toggle("reduce",R),e.reducedMotion&&q()),le()},spin(e){Number.isFinite(e)&&(X(),q(),A(H+e))},release(){X(),ce=setTimeout(We,2500)},strip(e){Number.isFinite(e)&&(Y=!0,V(e,!0))},stripRelease(e){Y=!1,V(Number.isFinite(e)?e:se(L(D,y)),!1)}};V(0,!1);const Ne={name:"JeepFloor",uniforms:{color:{value:null},tDiffuse:{value:null},textureMatrix:{value:null},strength:{value:.3},glow:{value:new k(.08,.083,.09)},radius:{value:new xe(2.7,4)},light:{value:0},dayFloor:{value:new k(.86,.86,.875)},dayStrength:{value:.34}},vertexShader:`
    uniform mat4 textureMatrix;
    varying vec4 vUv;
    varying vec2 vXZ;
    #include <common>
    #include <logdepthbuf_pars_vertex>
    void main() {
      vUv = textureMatrix * vec4(position, 1.0);
      vXZ = (modelMatrix * vec4(position, 1.0)).xz;
      gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
      #include <logdepthbuf_vertex>
    }`,fragmentShader:`
    uniform vec3 color;
    uniform sampler2D tDiffuse;
    uniform float strength;
    uniform vec3 glow;
    uniform vec2 radius;
    uniform float light;
    uniform vec3 dayFloor;
    uniform float dayStrength;
    varying vec4 vUv;
    varying vec2 vXZ;
    #include <logdepthbuf_pars_fragment>
    void main() {
      #include <logdepthbuf_fragment>
      float r = length(vXZ / radius);
      float fade = 1.0 - smoothstep(0.35, 1.0, r);   // reflection dies off near the car
      float pool = 1.0 - smoothstep(0.0, 1.05, r);   // the light pool reaches a little further
      vec4 tex = texture2DProj(tDiffuse, vUv);
      vec3 refl = mix(tex.rgb, vec3(dot(tex.rgb, vec3(0.2126, 0.7152, 0.0722))), 0.85);  // a near-neutral reflection: no beige chassis showing

      // night: premultiplied, so on a black page this is exactly the colour; elsewhere a dark glaze
      gl_FragColor = vec4(refl * color * strength * fade * fade + glow * pool * pool, 1.0);
      #include <tonemapping_fragment>
      #include <colorspace_fragment>
      vec4 night = vec4(gl_FragColor.rgb, pool);

      // day: a pale grey glaze with the Jeep mirrored in it where the reflection has the car (alpha)
      gl_FragColor = vec4(refl * color, 1.0);
      #include <tonemapping_fragment>
      #include <colorspace_fragment>
      float cov = tex.a * dayStrength * fade * fade;
      float base = 0.55 * pool * pool;
      vec4 day = vec4(gl_FragColor.rgb * cov + dayFloor * base * (1.0 - cov), cov + base * (1.0 - cov));

      gl_FragColor = mix(night, day, light);
    }`};function qe(e,t){const r=document.createElement("canvas");r.width=256,r.height=512;const a=r.getContext("2d"),n=70;a.shadowColor="rgba(0,0,0,1)",a.shadowBlur=46,a.shadowOffsetX=1e3,a.fillStyle="#000",a.beginPath(),a.roundRect(n-1e3,n,256-2*n,512-2*n,40),a.fill();const f=new Pe(r),x=256/(256-2*n),h=new B(new Z(e*x,t*(512/(512-2*n))),new j({map:f,color:0,transparent:!0,opacity:1,depthWrite:!1}));return h.rotation.x=-Math.PI/2,h}function Xe(e){const t=new Fe;t.add(new B(new Oe(30,32,16),new j({color:new k(.012,.012,.014),side:ke})));const r=(x,h,u,C,p,m)=>{const i=new B(new Z(x,h),new j({color:new k(...u).multiplyScalar(C),side:De}));i.position.set(...p),i.lookAt(...m),t.add(i)};r(2,9,[1,1,1],2.2,[0,9,0],[0,0,0]),r(7,2.2,[1,1,1],.9,[7,3.5,5],[0,1,0]),r(9,.9,[.8,.88,1],1.8,[-8,1.6,-8],[0,1,0]);const a=new B(new Re(7,48),new j({color:new k(1.1,1.1,1.15)}));a.rotation.x=-Math.PI/2,a.position.y=-.6,t.add(a),r(14,1.2,[1,1,1],.35,[0,1.2,12],[0,1,0]);const n=new Ce(e),f=n.fromScene(t,.03).texture;return n.dispose(),f}async function Ye(){const e=await ye(U,{url:new URL("model/jeep.glb",document.baseURI).href,onProgress:o=>G({type:"progress",value:o})}),t=e.root.parent;e.renderer.setClearColor(0,0),e.controls.enabled=!1,e.setNight(!1),t.environment=Xe(e.renderer);const r=new Q;e.root.traverse(o=>{o.isMesh&&o.castShadow&&r.union(new Q().setFromObject(o))});const a=r.getSize(new M),n=r.getCenter(new M),f=new z(new Z(24,24),{textureWidth:1024,textureHeight:1024,color:16777215,clipBias:.002,shader:Ne});f.rotation.x=-Math.PI/2,f.position.y=4e-4,Object.assign(f.material,{transparent:!0,depthWrite:!1,blending:be,blendSrc:te,blendDst:ee,blendSrcAlpha:te,blendDstAlpha:ee}),f.renderOrder=1,t.add(f),t.traverse(o=>{o.isMesh&&o.material?.type==="ShadowMaterial"&&(o.position.y=.003,o.material.opacity=.5,o.renderOrder=2)});const x=[];t.traverse(o=>{o.isMesh&&o.material?.type==="ShadowMaterial"&&x.push(o.material)});const h=qe(a.x*1.02,a.z*.98);h.position.set(n.x,.005,n.z),h.renderOrder=3,e.root.add(h),t.traverse(o=>{o.isDirectionalLight&&o.castShadow&&(o.intensity=1.1)}),e.renderer.toneMappingExposure=.9;const u=new Me(13623551,2.6);u.position.set(-6,2.6,-7),t.add(u);const C=new Se(16777215,14211292,0);t.add(C);const p=[];t.traverse(o=>{o.isDirectionalLight&&o.castShadow&&p.push(o)});const m=[];t.traverse(o=>{o.isDirectionalLight&&!o.castShadow&&o!==u&&m.push([o,o.intensity])});const i=(o,s,l)=>o+(s-o)*l;let P=0,v=0;function F(o){P=o,f.material.uniforms.light.value=o,h.material.opacity=i(1,.5,o);for(const s of x)s.opacity=i(.5,.18,o);for(const s of p)s.intensity=i(1.1,2.4,o);for(const[s,l]of m)s.intensity=l*i(1,2.2,o);u.intensity=i(2.6,1.2,o),C.intensity=i(0,.9,o),t.environmentIntensity=i(1,1.5,o),e.renderer.toneMappingExposure=i(.9,1,o),e.kick()}let d=!1;e.setTheme=o=>{const s=o==="light"?1:0,l=P;if(cancelAnimationFrame(v),!d||R){d=!0,F(s);return}const _=performance.now(),O=c=>{const E=Math.min(1,(c-_)/300);F(i(l,s,E)),v=E<1?requestAnimationFrame(O):0};v=requestAnimationFrame(O)},e.setTheme(y.theme==="light"?"light":"dark"),D.theme=y.theme==="light"?"light":"dark",d=!0,e.cam.zoom=Number(I.get("zoom"))||1.22;const b=()=>{const o=U.clientWidth,s=U.clientHeight;!o||!s||(e.cam.setViewOffset(o,s,o*.035,s*.03,o,s),e.cam.updateProjectionMatrix(),e.kick())};b(),new ResizeObserver(b).observe(U),S=e,A(H),le();const w=I.get("view")||"top";w==="top"&&I.get("settle")==="0"?e.setView("top",1):w==="top"&&!R?(e.setView("top",1),ie=setTimeout(q,2400)):(N=!0,e.setView(w==="top"?"hero":w,1)),e.kick(),G({type:"ready"})}Ye().catch(e=>G({type:"error",message:String(e)}));
