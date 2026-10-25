import{M as U,P as ye,C,a as xe,V as M,W as Me,H as be,S as Se,U as Fe,b as oe,c as re,d as Re,B as ae,e as ee,f as ne,O as ie,g as se,h as Oe,D as Pe,i as _e,j as ke,k as Ce,l as j,m as De,n as Te,o as We,p as Be,q as Ee,r as Ue}from"./jeep-CtNpGlJ6.js";class q extends U{constructor(t,r={}){super(t),this.isReflector=!0,this.type="Reflector",this.camera=new ye;const a=this,n=r.color!==void 0?new C(r.color):new C(8355711),l=r.textureWidth||512,d=r.textureHeight||512,s=r.clipBias||0,u=r.shader||q.ReflectorShader,p=r.multisample!==void 0?r.multisample:4,m=new xe,g=new M,h=new M,T=new M,F=new oe,R=new M(0,0,-1),v=new re,x=new M,k=new M,O=new re,P=new oe,c=this.camera,o=new Me(l,d,{samples:p,type:be}),i=new Se({name:u.name!==void 0?u.name:"unspecified",uniforms:Fe.clone(u.uniforms),fragmentShader:u.fragmentShader,vertexShader:u.vertexShader});i.uniforms.tDiffuse.value=o.texture,i.uniforms.color.value=n,i.uniforms.textureMatrix.value=P,this.material=i,this.onBeforeRender=function(f,X,_){if(h.setFromMatrixPosition(a.matrixWorld),T.setFromMatrixPosition(_.matrixWorld),F.extractRotation(a.matrixWorld),g.set(0,0,1),g.applyMatrix4(F),x.subVectors(h,T),x.dot(g)>0)return;x.reflect(g).negate(),x.add(h),F.extractRotation(_.matrixWorld),R.set(0,0,-1),R.applyMatrix4(F),R.add(T),k.subVectors(h,R),k.reflect(g).negate(),k.add(h),c.position.copy(x),c.up.set(0,1,0),c.up.applyMatrix4(F),c.up.reflect(g),c.lookAt(k),c.far=_.far,c.updateMatrixWorld(),c.projectionMatrix.copy(_.projectionMatrix),P.set(.5,0,0,.5,0,.5,0,.5,0,0,.5,.5,0,0,0,1),P.multiply(c.projectionMatrix),P.multiply(c.matrixWorldInverse),P.multiply(a.matrixWorld),m.setFromNormalAndCoplanarPoint(g,h),m.applyMatrix4(c.matrixWorldInverse),v.set(m.normal.x,m.normal.y,m.normal.z,m.constant);const w=c.projectionMatrix;O.x=(Math.sign(v.x)+w.elements[8])/w.elements[0],O.y=(Math.sign(v.y)+w.elements[9])/w.elements[5],O.z=-1,O.w=(1+w.elements[10])/w.elements[14],v.multiplyScalar(2/v.dot(O)),w.elements[2]=v.x,w.elements[6]=v.y,w.elements[10]=v.z+1-s,w.elements[14]=v.w,a.visible=!1;const L=f.getRenderTarget(),ve=f.xr.enabled,we=f.shadowMap.autoUpdate;f.xr.enabled=!1,f.shadowMap.autoUpdate=!1,f.setRenderTarget(o),f.state.buffers.depth.setMask(!0),f.autoClear===!1&&f.clear(),f.render(X,c),f.xr.enabled=ve,f.shadowMap.autoUpdate=we,f.setRenderTarget(L);const te=_.viewport;te!==void 0&&f.state.viewport(te),a.visible=!0},this.getRenderTarget=function(){return o},this.dispose=function(){o.dispose(),a.material.dispose()}}}q.ReflectorShader={name:"ReflectorShader",uniforms:{color:{value:null},tDiffuse:{value:null},textureMatrix:{value:null}},vertexShader:`
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

		}`};const de=["on","panels","off"],Le=["FL","FR","BL","BR"],je=["dark","light"];function Ie(e={},t={}){const r=[];if(je.includes(t.theme)&&t.theme!==(e.theme??"dark")&&r.push(["setTheme",t.theme]),typeof t.lights=="boolean"&&t.lights!==!!e.lights&&r.push(["setLights",t.lights]),de.includes(t.roof)&&t.roof!==(e.roof??"on")&&r.push(["setRoof",t.roof]),typeof t.doorsOff=="boolean"&&t.doorsOff!==!!e.doorsOff&&r.push(["setDoorsOff",t.doorsOff]),t.doors)for(const a of Le){const n=t.doors[a];typeof n=="boolean"&&n!==!!e.doors?.[a]&&r.push(["setDoor",a,n])}return typeof t.gate=="boolean"&&t.gate!==!!e.gate&&r.push(["setGate",t.gate]),r}const le=[{key:"on",label:"Top on"},{key:"panels",label:"Panels"},{key:"off",label:"Top off"},{key:"doorsOff",label:"Doors off"}];function ue(e={}){if(e.doorsOff)return 3;const t=de.indexOf(e.roof??"on");return t<0?0:t}function Ve(e){let t=e%360;return t>180&&(t-=360),t<=-180&&(t+=360),t}function Ae(e,t,r,a=0){if(!(e>0)||!(r>0))return 0;const n=Math.tan(t*Math.PI/360)*(1-2*Math.min(Math.max(a,0),.45)),l=Math.min(n,n*r);return e*Math.sqrt(1+l*l)/l}const W=document.getElementById("c"),ce=new URLSearchParams(location.search),J=e=>window.webkit?.messageHandlers?.jeep?.postMessage(e),ze={theme:"dark",lights:!1,roof:"on",doorsOff:!1,doors:{FL:!1,FR:!1,BL:!1,BR:!1},gate:!1};let B=structuredClone(ze),b={},S=null,D=!!window.matchMedia?.("(prefers-reduced-motion: reduce)").matches,me=0,Y=!1;const V=(e,t)=>({...e,...t,...t.doors?{doors:{...e.doors,...t.doors}}:{}});function $(){clearTimeout(me),!(Y||!S)&&(Y=!0,S.setView("hero",D?1:1600))}function he(){const e=b.theme==="light"?"light":"dark";if(document.documentElement.dataset.theme=e,Q||H(ue(V(B,b)),!1),!!S){for(const[t,...r]of Ie(B,b))S[t](...r);B=V(B,b)}}const He=e=>e<.5?4*e*e*e:1-Math.pow(-2*e+2,3)/2;let G=0,A=0,pe=0,E=null;function z(e){G=e,S&&(S.root.rotation.y=Ee.degToRad(e),E&&(E.yaw.value=S.root.rotation.y),S.kick())}function K(){cancelAnimationFrame(A),A=0,clearTimeout(pe)}function qe(){K();const e=Ve(G);if(D||Math.abs(e)<.05){z(0);return}const t=performance.now(),r=a=>{const n=Math.min(1,(a-t)/900);z(e*(1-He(n))),A=n<1?requestAnimationFrame(r):0};A=requestAnimationFrame(r)}const N=document.getElementById("strip"),Ge=document.getElementById("puck"),Z=document.getElementById("strip-label"),Xe=['<rect x="7" y="13" width="18" height="26" rx="3" fill="currentColor" opacity=".9"/>','<rect x="7" y="23" width="18" height="16" rx="3" fill="currentColor" opacity=".9"/>',"",""],Ne='<rect x="3" y="2" width="26" height="52" rx="9" fill="none" stroke="currentColor" stroke-width="2"/>',Ze='<path d="M3 17V11a9 9 0 0 1 9-9h8a9 9 0 0 1 9 9v6M3 41v4a9 9 0 0 0 9 9h8a9 9 0 0 0 9-9v-4" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>',Je=e=>`<svg viewBox="0 0 32 56" aria-hidden="true">${e===3?Ze:Ne}${Xe[e]}<path d="M8 8h16" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>`;let fe=-1,Q=!1;function H(e,t){const r=le.length-1,a=Math.round(Math.min(r,Math.max(0,e)));N.classList.toggle("live",t),N.style.setProperty("--pos",String(Math.min(r,Math.max(0,e))/r)),a!==fe&&(fe=a,Ge.innerHTML=Je(a),Z.textContent=le[a].label,Z.style.marginLeft=`${-Math.max(0,Z.offsetWidth/2-(N.offsetWidth/2-2))}px`)}window.jeepEmbed={apply(e={}){b=V(b,e),typeof e.reducedMotion=="boolean"&&(D=e.reducedMotion||D,document.documentElement.classList.toggle("reduce",D),e.reducedMotion&&$()),he()},spin(e){Number.isFinite(e)&&(K(),$(),z(G+e))},release(){K(),pe=setTimeout(qe,2500)},strip(e){Number.isFinite(e)&&(Q=!0,H(e,!0))},stripRelease(e){Q=!1,H(Number.isFinite(e)?e:ue(V(B,b)),!1)}};H(0,!1);const Ye={name:"JeepFloor",uniforms:{color:{value:null},tDiffuse:{value:null},textureMatrix:{value:null},strength:{value:.25},glow:{value:new C(.05,.052,.058)},foot:{value:new ne(1,2.4)},centre:{value:new ne(0,0)},reach:{value:.7},yaw:{value:0},light:{value:0},dayFloor:{value:new C(.86,.86,.875)},dayStrength:{value:.18}},vertexShader:`
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
    uniform vec2 foot;
    uniform vec2 centre;
    uniform float reach;
    uniform float yaw;
    uniform float light;
    uniform vec3 dayFloor;
    uniform float dayStrength;
    varying vec4 vUv;
    varying vec2 vXZ;
    #include <logdepthbuf_pars_fragment>
    void main() {
      #include <logdepthbuf_fragment>
      // distance from the footprint (a rounded box in the Jeep's own frame; negative under the car)
      float c = cos(yaw), s = sin(yaw);
      vec2 p = vec2(c * vXZ.x - s * vXZ.y, s * vXZ.x + c * vXZ.y) - centre;
      vec2 q = abs(p) - foot;
      float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
      float fade = 1.0 - smoothstep(-0.15, reach, d);        // the reflection dies off close to the car
      float pool = 1.0 - smoothstep(-0.8, reach * 1.4, d);   // the light pool reaches a little further
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
    }`};function $e(e,t){const r=document.createElement("canvas");r.width=256,r.height=512;const a=r.getContext("2d"),n=70;a.shadowColor="rgba(0,0,0,1)",a.shadowBlur=46,a.shadowOffsetX=1e3,a.fillStyle="#000",a.beginPath(),a.roundRect(n-1e3,n,256-2*n,512-2*n,40),a.fill();const l=new Be(r),d=256/(256-2*n),s=new U(new ee(e*d,t*(512/(512-2*n))),new j({map:l,color:0,transparent:!0,opacity:1,depthWrite:!1}));return s.rotation.x=-Math.PI/2,s}function Ke(e){const t=new ke;t.add(new U(new Ce(30,32,16),new j({color:new C(.012,.012,.014),side:De})));const r=(d,s,u,p,m,g)=>{const h=new U(new ee(d,s),new j({color:new C(...u).multiplyScalar(p),side:Ue}));h.position.set(...m),h.lookAt(...g),t.add(h)};r(3,11,[1,1,1],6,[0,8,0],[0,0,0]),r(12,3.2,[1,1,1],14,[-7,7.5,-9],[0,1,0]),r(7,2.2,[1,1,1],.9,[7,3.5,5],[0,1,0]),r(9,.9,[.8,.88,1],1.8,[-8,1.6,-8],[0,1,0]),r(14,.8,[1,1,1],11,[-7,.7,7],[0,.7,0]);const a=new U(new Te(7,48),new j({color:new C(1.1,1.1,1.15)}));a.rotation.x=-Math.PI/2,a.position.y=-.6,t.add(a),r(14,1.2,[1,1,1],.35,[0,1.2,12],[0,1,0]);const n=new We(e),l=n.fromScene(t,.03).texture;return n.dispose(),l}const ge=44,Qe=.08;let I=null;function et(e){e.updateMatrixWorld(!0);const t=new M,r=[];let a=1/0,n=-1/0;e.traverse(s=>{if(!s.isMesh||!s.castShadow)return;const u=s.geometry.attributes.position;for(let p=0;p<u.count;p++)t.fromBufferAttribute(u,p).applyMatrix4(s.matrixWorld),r.push(Math.hypot(t.x,t.z),t.y),a=Math.min(a,t.y),n=Math.max(n,t.y)});const l=(a+n)/2;let d=0;for(let s=0;s<r.length;s+=2)d=Math.max(d,r[s]*r[s]+(r[s+1]-l)**2);return{r:Math.sqrt(d),y:l}}function tt(){if(!I)return null;const e=W.clientWidth,t=W.clientHeight;return!e||!t?null:{d:Ae(I.r,24,Math.max(1,e-ge)/t,Qe),y:I.y}}const y=(e,t,r)=>e+(t-e)*r;async function ot(){const e=await Re(W,{url:new URL("model/jeep.glb",document.baseURI).href,onProgress:o=>J({type:"progress",value:o}),fitView:tt}),t=e.root.parent;e.renderer.setClearColor(0,0),e.controls.enabled=!1,e.setNight(!1),t.environment=Ke(e.renderer);const r=new Set;e.root.traverse(o=>{if(o.isMesh)for(const i of[].concat(o.material))i.name==="JMI_1355060001_004"&&r.add(i)});const a=o=>{for(const i of r)i.metalness=y(.15,.55,o),i.roughness=y(.1,.2,o),i.isMeshPhysicalMaterial&&(i.clearcoat=y(1,0,o),i.clearcoatRoughness=.04)},n=new ae;e.root.traverse(o=>{o.isMesh&&o.castShadow&&n.union(new ae().setFromObject(o))});const l=n.getSize(new M),d=n.getCenter(new M),s=new q(new ee(24,24),{textureWidth:1024,textureHeight:1024,color:16777215,clipBias:.002,shader:Ye});s.rotation.x=-Math.PI/2,s.position.y=4e-4,Object.assign(s.material,{transparent:!0,depthWrite:!1,blending:Oe,blendSrc:se,blendDst:ie,blendSrcAlpha:se,blendDstAlpha:ie}),s.renderOrder=1,t.add(s),E=s.material.uniforms,E.foot.value.set(l.x/2,l.z/2),E.centre.value.set(d.x,d.z),E.reach.value=l.y*.35,t.traverse(o=>{o.isMesh&&o.material?.type==="ShadowMaterial"&&(o.position.y=.003,o.material.opacity=.5,o.renderOrder=2)});const u=[];t.traverse(o=>{o.isMesh&&o.material?.type==="ShadowMaterial"&&u.push(o.material)});const p=$e(l.x*1.02,l.z*.98);p.position.set(d.x,.005,d.z),p.renderOrder=3,e.root.add(p),t.traverse(o=>{o.isDirectionalLight&&o.castShadow&&(o.intensity=1.1)}),e.renderer.toneMappingExposure=1.1;const m=new Pe(13623551,2.6);m.position.set(-6,2.6,-7),t.add(m);const g=new _e(16777215,14211292,0);t.add(g);const h=[];t.traverse(o=>{o.isDirectionalLight&&o.castShadow&&h.push(o)});const T=[];t.traverse(o=>{o.isDirectionalLight&&!o.castShadow&&o!==m&&T.push([o,o.intensity])});let F=0,R=0;function v(o){F=o,a(o),s.material.uniforms.light.value=o,p.material.opacity=y(1,.5,o);for(const i of u)i.opacity=y(.5,.18,o);for(const i of h)i.intensity=y(1.1,2.4,o);for(const[i,f]of T)i.intensity=f*y(1,2.2,o);m.intensity=y(2.6,1.2,o),g.intensity=y(0,.9,o),t.environmentIntensity=y(1,1.5,o),e.renderer.toneMappingExposure=y(1.1,1,o),e.kick()}let x=!1;e.setTheme=o=>{const i=o==="light"?1:0,f=F;if(cancelAnimationFrame(R),!x||D){x=!0,v(i);return}const X=performance.now(),_=w=>{const L=Math.min(1,(w-X)/300);v(y(f,i,L)),R=L<1?requestAnimationFrame(_):0};R=requestAnimationFrame(_)},e.setTheme(b.theme==="light"?"light":"dark"),B.theme=b.theme==="light"?"light":"dark",x=!0,I=et(e.root);let k="hero";const O=e.setView;e.setView=(o,i)=>{k=o,O(o,i)};const P=()=>{const o=W.clientWidth,i=W.clientHeight;!o||!i||(e.cam.zoom=1,e.cam.setViewOffset(o,i,ge/2,0,o,i),e.cam.updateProjectionMatrix(),O(k,1),e.kick())};P(),new ResizeObserver(P).observe(W),S=e,z(G),he();const c=ce.get("view")||"top";c==="top"&&ce.get("settle")==="0"?e.setView("top",1):c==="top"&&!D?(e.setView("top",1),me=setTimeout($,2400)):(Y=!0,e.setView(c==="top"?"hero":c,1)),e.kick(),J({type:"ready"})}ot().catch(e=>J({type:"error",message:String(e)}));
