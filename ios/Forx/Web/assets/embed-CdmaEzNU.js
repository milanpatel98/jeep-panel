import{M as z,P as me,C as T,a as he,V as A,W as pe,H as ge,S as ve,U as we,b as ae,c as ne,d as ye,B as J,e as oe,f as re,O as se,g as ie,h as xe,D as Me,i as be,j as Se,k as Fe,l as L,m as Re,n as _e,o as Oe,p as Pe,q as Ce,r as De}from"./jeep-CDNWbL8X.js";class Z extends z{constructor(o,a={}){super(o),this.isReflector=!0,this.type="Reflector",this.camera=new me;const r=this,s=a.color!==void 0?new T(a.color):new T(8355711),h=a.textureWidth||512,p=a.textureHeight||512,u=a.clipBias||0,d=a.shader||Z.ReflectorShader,x=a.multisample!==void 0?a.multisample:4,f=new he,l=new A,v=new A,P=new A,R=new ae,C=new A(0,0,-1),g=new ne,b=new A,D=new A,S=new ne,M=new ae,i=this.camera,t=new pe(h,p,{samples:x,type:ge}),n=new ve({name:d.name!==void 0?d.name:"unspecified",uniforms:we.clone(d.uniforms),fragmentShader:d.fragmentShader,vertexShader:d.vertexShader});n.uniforms.tDiffuse.value=t.texture,n.uniforms.color.value=s,n.uniforms.textureMatrix.value=M,this.material=n,this.onBeforeRender=function(c,_,w){if(v.setFromMatrixPosition(r.matrixWorld),P.setFromMatrixPosition(w.matrixWorld),R.extractRotation(r.matrixWorld),l.set(0,0,1),l.applyMatrix4(R),b.subVectors(v,P),b.dot(l)>0)return;b.reflect(l).negate(),b.add(v),R.extractRotation(w.matrixWorld),C.set(0,0,-1),C.applyMatrix4(R),C.add(P),D.subVectors(v,C),D.reflect(l).negate(),D.add(v),i.position.copy(b),i.up.set(0,1,0),i.up.applyMatrix4(R),i.up.reflect(l),i.lookAt(D),i.far=w.far,i.updateMatrixWorld(),i.projectionMatrix.copy(w.projectionMatrix),M.set(.5,0,0,.5,0,.5,0,.5,0,0,.5,.5,0,0,0,1),M.multiply(i.projectionMatrix),M.multiply(i.matrixWorldInverse),M.multiply(r.matrixWorld),f.setFromNormalAndCoplanarPoint(l,v),f.applyMatrix4(i.matrixWorldInverse),g.set(f.normal.x,f.normal.y,f.normal.z,f.constant);const m=i.projectionMatrix;S.x=(Math.sign(g.x)+m.elements[8])/m.elements[0],S.y=(Math.sign(g.y)+m.elements[9])/m.elements[5],S.z=-1,S.w=(1+m.elements[10])/m.elements[14],g.multiplyScalar(2/g.dot(S)),m.elements[2]=g.x,m.elements[6]=g.y,m.elements[10]=g.z+1-u,m.elements[14]=g.w,r.visible=!1;const y=c.getRenderTarget(),B=c.xr.enabled,I=c.shadowMap.autoUpdate;c.xr.enabled=!1,c.shadowMap.autoUpdate=!1,c.setRenderTarget(t),c.state.buffers.depth.setMask(!0),c.autoClear===!1&&c.clear(),c.render(_,i),c.xr.enabled=B,c.shadowMap.autoUpdate=I,c.setRenderTarget(y);const k=w.viewport;k!==void 0&&c.state.viewport(k),r.visible=!0},this.getRenderTarget=function(){return t},this.dispose=function(){t.dispose(),r.material.dispose()}}}Z.ReflectorShader={name:"ReflectorShader",uniforms:{color:{value:null},tDiffuse:{value:null},textureMatrix:{value:null}},vertexShader:`
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

		}`};const Ae=["on","panels","off"],Te=["FL","FR","BL","BR"],Ue=["dark","light"];function We(e={},o={}){const a=[];if(Ue.includes(o.theme)&&o.theme!==(e.theme??"dark")&&a.push(["setTheme",o.theme]),typeof o.lights=="boolean"&&o.lights!==!!e.lights&&a.push(["setLights",o.lights]),Ae.includes(o.roof)&&o.roof!==(e.roof??"on")&&a.push(["setRoof",o.roof]),typeof o.doorsOff=="boolean"&&o.doorsOff!==!!e.doorsOff&&a.push(["setDoorsOff",o.doorsOff]),o.doors)for(const r of Te){const s=o.doors[r];typeof s=="boolean"&&s!==!!e.doors?.[r]&&a.push(["setDoor",r,s])}return typeof o.gate=="boolean"&&o.gate!==!!e.gate&&a.push(["setGate",o.gate]),a}function je(e){let o=e%360;return o>180&&(o-=360),o<=-180&&(o+=360),o}function Ve(e,{az:o,el:a,ty:r=0,fovDeg:s,aspect:h,margin:p=0,yaws:u=[0]}){const d=Math.PI/180,x=[Math.cos(a*d)*Math.sin(o*d),Math.sin(a*d),Math.cos(a*d)*Math.cos(o*d)],f=x.map(t=>-t);let l=[-f[2],0,f[0]];const v=Math.hypot(l[0],l[2])||1;l=l.map(t=>t/v);const P=[l[1]*f[2]-l[2]*f[1],l[2]*f[0]-l[0]*f[2],l[0]*f[1]-l[1]*f[0]],R=Math.tan(s*d/2),C=R*h,g=[];for(const t of u){const n=Math.cos(t*d),c=Math.sin(t*d);for(const[_,w,m]of e)g.push([_*n+m*c,w-r,-_*c+m*n])}const b=t=>{let n=1/0,c=-1/0,_=1/0,w=-1/0;for(const m of g){const y=[m[0]-x[0]*t,m[1]-x[1]*t,m[2]-x[2]*t],B=y[0]*f[0]+y[1]*f[1]+y[2]*f[2],I=(y[0]*l[0]+y[1]*l[1]+y[2]*l[2])/(B*C),k=(y[0]*P[0]+y[1]*P[1]+y[2]*P[2])/(B*R);n=Math.min(n,I),c=Math.max(c,I),_=Math.min(_,k),w=Math.max(w,k)}return{x0:n,x1:c,y0:_,y1:w,half:Math.max((c-n)/2,(w-_)/2)}},D=1-2*Math.min(Math.max(p,0),.45);let S=Math.max(...g.map(t=>Math.hypot(...t)))*1.05,M=S*40;for(let t=0;t<32;t++){const n=(S+M)/2;b(n).half>D?S=n:M=n}const i=b(M);return{d:M,cx:(i.x0+i.x1)/2,cy:(i.y0+i.y1)/2,hx:(i.x1-i.x0)/2,hy:(i.y1-i.y0)/2}}function ke(e,o){const a=[];for(const r of[e[0],o[0]])for(const s of[e[1],o[1]])for(const h of[e[2],o[2]])a.push([r,s,h]);return a}const j=document.getElementById("c"),le=new URLSearchParams(location.search),Y=e=>window.webkit?.messageHandlers?.jeep?.postMessage(e),ze={theme:"dark",lights:!1,roof:"on",doorsOff:!1,doors:{FL:!1,FR:!1,BL:!1,BR:!1},gate:!1};let E=structuredClone(ze),U={},O=null,W=!!window.matchMedia?.("(prefers-reduced-motion: reduce)").matches,ce=0,H=!1;const fe=(e,o)=>({...e,...o,...o.doors?{doors:{...e.doors,...o.doors}}:{}});function K(){clearTimeout(ce),!(H||!O)&&(H=!0,O.setView("hero",W?1:1600))}function de(){const e=U.theme==="light"?"light":"dark";if(document.documentElement.dataset.theme=e,!!O){for(const[o,...a]of We(E,U))O[o](...a);E=fe(E,U)}}const Be=e=>e<.5?4*e*e*e:1-Math.pow(-2*e+2,3)/2;let N=0,q=0,ue=0,V=null;function X(e){N=e,O&&(O.root.rotation.y=Ce.degToRad(e),V&&(V.yaw.value=O.root.rotation.y),O.kick())}function Q(){cancelAnimationFrame(q),q=0,clearTimeout(ue)}let $=!1;function ee(e,o){$!==e&&($=e,O&&H&&O.setView("hero",W?1:o))}function Ie(){Q();const e=je(N);if(W||Math.abs(e)<.05){X(0),ee(!1,500);return}const o=performance.now(),a=r=>{const s=Math.min(1,(r-o)/900);X(e*(1-Be(s))),q=s<1?requestAnimationFrame(a):0,s>=1&&ee(!1,500)};q=requestAnimationFrame(a)}window.jeepEmbed={apply(e={}){U=fe(U,e),typeof e.reducedMotion=="boolean"&&(W=e.reducedMotion||W,e.reducedMotion&&K()),de()},spin(e){Number.isFinite(e)&&(Q(),K(),ee(!0,300),X(N+e))},release(){Q(),ue=setTimeout(Ie,2500)}};const Le={name:"JeepFloor",uniforms:{color:{value:null},tDiffuse:{value:null},textureMatrix:{value:null},strength:{value:.25},glow:{value:new T(.05,.052,.058)},foot:{value:new re(1,2.4)},centre:{value:new re(0,0)},reach:{value:.7},yaw:{value:0},light:{value:0},dayFloor:{value:new T(.86,.86,.875)},dayStrength:{value:.18}},vertexShader:`
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
    }`};function Ee(e,o){const a=document.createElement("canvas");a.width=256,a.height=512;const r=a.getContext("2d"),s=70;r.shadowColor="rgba(0,0,0,1)",r.shadowBlur=46,r.shadowOffsetX=1e3,r.fillStyle="#000",r.beginPath(),r.roundRect(s-1e3,s,256-2*s,512-2*s,40),r.fill();const h=new Pe(a),p=256/(256-2*s),u=new z(new oe(e*p,o*(512/(512-2*s))),new L({map:h,color:0,transparent:!0,opacity:1,depthWrite:!1}));return u.rotation.x=-Math.PI/2,u}function He(e){const o=new Se;o.add(new z(new Fe(30,32,16),new L({color:new T(.012,.012,.014),side:Re})));const a=(p,u,d,x,f,l)=>{const v=new z(new oe(p,u),new L({color:new T(...d).multiplyScalar(x),side:De}));v.position.set(...f),v.lookAt(...l),o.add(v)};a(1.2,11,[1,1,1],2.2,[0,8,0],[0,0,0]);for(const[p,u]of[[6.4,9],[7.6,12],[8.8,9]])a(13,.22,[1,1,1],u,[-7,p,-9],[0,1,0]);a(7,2.2,[1,1,1],.9,[7,3.5,5],[0,1,0]),a(9,.9,[.8,.88,1],1.8,[-8,1.6,-8],[0,1,0]),a(14,.8,[1,1,1],11,[-7,.7,7],[0,.7,0]);const r=new z(new _e(7,48),new L({color:new T(1.1,1.1,1.15)}));r.rotation.x=-Math.PI/2,r.position.y=-.6,o.add(r),a(14,1.2,[1,1,1],.35,[0,1.2,12],[0,1,0]);const s=new Oe(e),h=s.fromScene(o,.03).texture;return s.dispose(),h}const qe=.06,Xe=Array.from({length:24},(e,o)=>o*15);let G=null,te=0;function Ge(e,o){if(!G)return null;const a=j.clientWidth,r=j.clientHeight;if(!a||!r)return null;const s=$&&e!=="top"?Xe:[0],h=(p,u)=>{const d=Ve(G,{az:p,el:u,ty:te,fovDeg:24,aspect:a/r,margin:qe,yaws:s});return{d:d.d,offset:[d.cx*a/2,-d.cy*r/2]}};return{...h(o.az,o.el),y:te,fitAt:h}}const F=(e,o,a)=>e+(o-e)*a;async function Ze(){const e=await ye(j,{url:new URL("model/jeep.glb",document.baseURI).href,onProgress:t=>Y({type:"progress",value:t}),fitView:Ge}),o=e.root.parent;e.renderer.setClearColor(0,0),e.controls.enabled=!1,e.setNight(!1),o.environment=He(e.renderer);const a=new Set;e.root.traverse(t=>{if(t.isMesh)for(const n of[].concat(t.material))n.name==="JMI_1355060001_004"&&a.add(n)});const r=t=>{for(const n of a)n.metalness=F(.15,.55,t),n.roughness=F(.1,.2,t),n.isMeshPhysicalMaterial&&(n.clearcoat=F(1,0,t),n.clearcoatRoughness=.04)},s=new J;e.root.traverse(t=>{t.isMesh&&t.castShadow&&s.union(new J().setFromObject(t))});const h=s.getSize(new A),p=s.getCenter(new A),u=new Z(new oe(24,24),{textureWidth:1024,textureHeight:1024,color:16777215,clipBias:.002,shader:Le});u.rotation.x=-Math.PI/2,u.position.y=4e-4,Object.assign(u.material,{transparent:!0,depthWrite:!1,blending:xe,blendSrc:ie,blendDst:se,blendSrcAlpha:ie,blendDstAlpha:se}),u.renderOrder=1,o.add(u),V=u.material.uniforms,V.foot.value.set(h.x/2,h.z/2),V.centre.value.set(p.x,p.z),V.reach.value=h.y*.35,o.traverse(t=>{t.isMesh&&t.material?.type==="ShadowMaterial"&&(t.position.y=.003,t.material.opacity=.5,t.renderOrder=2)});const d=[];o.traverse(t=>{t.isMesh&&t.material?.type==="ShadowMaterial"&&d.push(t.material)});const x=Ee(h.x*1.02,h.z*.98);x.position.set(p.x,.005,p.z),x.renderOrder=3,e.root.add(x),o.traverse(t=>{t.isDirectionalLight&&t.castShadow&&(t.intensity=1.1)}),e.renderer.toneMappingExposure=1.1;const f=new Me(13623551,2.6);f.position.set(-6,2.6,-7),o.add(f);const l=new be(16777215,14211292,0);o.add(l);const v=[];o.traverse(t=>{t.isDirectionalLight&&t.castShadow&&v.push(t)});const P=[];o.traverse(t=>{t.isDirectionalLight&&!t.castShadow&&t!==f&&P.push([t,t.intensity])});let R=0,C=0;function g(t){R=t,r(t),u.material.uniforms.light.value=t,x.material.opacity=F(1,.5,t);for(const n of d)n.opacity=F(.5,.18,t);for(const n of v)n.intensity=F(1.1,2.4,t);for(const[n,c]of P)n.intensity=c*F(1,2.2,t);f.intensity=F(2.6,1.2,t),l.intensity=F(0,.9,t),o.environmentIntensity=F(1,1.5,t),e.renderer.toneMappingExposure=F(1.1,1,t),e.kick()}let b=!1;e.setTheme=t=>{const n=t==="light"?1:0,c=R;if(cancelAnimationFrame(C),!b||W){b=!0,g(n);return}const _=performance.now(),w=m=>{const y=Math.min(1,(m-_)/300);g(F(c,n,y)),C=y<1?requestAnimationFrame(w):0};C=requestAnimationFrame(w)},e.setTheme(U.theme==="light"?"light":"dark"),E.theme=U.theme==="light"?"light":"dark",b=!0,G=[],e.root.traverse(t=>{if(t.isMesh&&t.castShadow){const n=new J().setFromObject(t);n.isEmpty()||G.push(...ke(n.min.toArray(),n.max.toArray()))}}),te=p.y;let D="hero";const S=e.setView;e.setView=(t,n)=>{D=t,S(t,n)};const M=()=>{!j.clientWidth||!j.clientHeight||(e.cam.zoom=1,S(D,1),e.kick())};M(),new ResizeObserver(M).observe(j),O=e,window.__jeep=e,X(N),de();const i=le.get("view")||"top";i==="top"&&le.get("settle")==="0"?e.setView("top",1):i==="top"&&!W?(e.setView("top",1),ce=setTimeout(K,2400)):(H=!0,e.setView(i==="top"?"hero":i,1)),e.kick(),Y({type:"ready"})}Ze().catch(e=>Y({type:"error",message:String(e)}));
