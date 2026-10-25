import{M as V,P as be,C as B,a as Se,V as T,W as Fe,H as Re,S as Oe,U as _e,b as le,c as ce,d as ke,B as Q,e as ie,f as fe,O as de,g as ue,h as Pe,D as Ce,i as De,j as Te,k as We,l as H,m as Be,n as Ae,o as Ee,p as Ie,q as Le,r as Ue}from"./jeep-CDNWbL8X.js";class $ extends V{constructor(o,n={}){super(o),this.isReflector=!0,this.type="Reflector",this.camera=new be;const a=this,i=n.color!==void 0?new B(n.color):new B(8355711),p=n.textureWidth||512,u=n.textureHeight||512,h=n.clipBias||0,d=n.shader||$.ReflectorShader,g=n.multisample!==void 0?n.multisample:4,l=new Se,s=new T,y=new T,k=new T,R=new le,P=new T(0,0,-1),v=new ce,b=new T,C=new T,S=new ce,M=new le,c=this.camera,t=new Fe(p,u,{samples:g,type:Re}),r=new Oe({name:d.name!==void 0?d.name:"unspecified",uniforms:_e.clone(d.uniforms),fragmentShader:d.fragmentShader,vertexShader:d.vertexShader});r.uniforms.tDiffuse.value=t.texture,r.uniforms.color.value=i,r.uniforms.textureMatrix.value=M,this.material=r,this.onBeforeRender=function(f,O,x){if(y.setFromMatrixPosition(a.matrixWorld),k.setFromMatrixPosition(x.matrixWorld),R.extractRotation(a.matrixWorld),s.set(0,0,1),s.applyMatrix4(R),b.subVectors(y,k),b.dot(s)>0)return;b.reflect(s).negate(),b.add(y),R.extractRotation(x.matrixWorld),P.set(0,0,-1),P.applyMatrix4(R),P.add(k),C.subVectors(y,P),C.reflect(s).negate(),C.add(y),c.position.copy(b),c.up.set(0,1,0),c.up.applyMatrix4(R),c.up.reflect(s),c.lookAt(C),c.far=x.far,c.updateMatrixWorld(),c.projectionMatrix.copy(x.projectionMatrix),M.set(.5,0,0,.5,0,.5,0,.5,0,0,.5,.5,0,0,0,1),M.multiply(c.projectionMatrix),M.multiply(c.matrixWorldInverse),M.multiply(a.matrixWorld),l.setFromNormalAndCoplanarPoint(s,y),l.applyMatrix4(c.matrixWorldInverse),v.set(l.normal.x,l.normal.y,l.normal.z,l.constant);const m=c.projectionMatrix;S.x=(Math.sign(v.x)+m.elements[8])/m.elements[0],S.y=(Math.sign(v.y)+m.elements[9])/m.elements[5],S.z=-1,S.w=(1+m.elements[10])/m.elements[14],v.multiplyScalar(2/v.dot(S)),m.elements[2]=v.x,m.elements[6]=v.y,m.elements[10]=v.z+1-h,m.elements[14]=v.w,a.visible=!1;const w=f.getRenderTarget(),j=f.xr.enabled,z=f.shadowMap.autoUpdate;f.xr.enabled=!1,f.shadowMap.autoUpdate=!1,f.setRenderTarget(t),f.state.buffers.depth.setMask(!0),f.autoClear===!1&&f.clear(),f.render(O,c),f.xr.enabled=j,f.shadowMap.autoUpdate=z,f.setRenderTarget(w);const U=x.viewport;U!==void 0&&f.state.viewport(U),a.visible=!0},this.getRenderTarget=function(){return t},this.dispose=function(){t.dispose(),a.material.dispose()}}}$.ReflectorShader={name:"ReflectorShader",uniforms:{color:{value:null},tDiffuse:{value:null},textureMatrix:{value:null}},vertexShader:`
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

		}`};const ve=["on","panels","off"],Ve=["FL","FR","BL","BR"],je=["dark","light"];function ze(e={},o={}){const n=[];if(je.includes(o.theme)&&o.theme!==(e.theme??"dark")&&n.push(["setTheme",o.theme]),typeof o.lights=="boolean"&&o.lights!==!!e.lights&&n.push(["setLights",o.lights]),ve.includes(o.roof)&&o.roof!==(e.roof??"on")&&n.push(["setRoof",o.roof]),typeof o.doorsOff=="boolean"&&o.doorsOff!==!!e.doorsOff&&n.push(["setDoorsOff",o.doorsOff]),o.doors)for(const a of Ve){const i=o.doors[a];typeof i=="boolean"&&i!==!!e.doors?.[a]&&n.push(["setDoor",a,i])}return typeof o.gate=="boolean"&&o.gate!==!!e.gate&&n.push(["setGate",o.gate]),n}const he=[{key:"on",label:"Top on"},{key:"panels",label:"Panels"},{key:"off",label:"Top off"},{key:"doorsOff",label:"Doors off"}];function ye(e={}){if(e.doorsOff)return 3;const o=ve.indexOf(e.roof??"on");return o<0?0:o}function He(e){let o=e%360;return o>180&&(o-=360),o<=-180&&(o+=360),o}function qe(e,{az:o,el:n,ty:a=0,fovDeg:i,aspect:p,margin:u=0,yaws:h=[0]}){const d=Math.PI/180,g=[Math.cos(n*d)*Math.sin(o*d),Math.sin(n*d),Math.cos(n*d)*Math.cos(o*d)],l=g.map(t=>-t);let s=[-l[2],0,l[0]];const y=Math.hypot(s[0],s[2])||1;s=s.map(t=>t/y);const k=[s[1]*l[2]-s[2]*l[1],s[2]*l[0]-s[0]*l[2],s[0]*l[1]-s[1]*l[0]],R=Math.tan(i*d/2),P=R*p,v=[];for(const t of h){const r=Math.cos(t*d),f=Math.sin(t*d);for(const[O,x,m]of e)v.push([O*r+m*f,x-a,-O*f+m*r])}const b=t=>{let r=1/0,f=-1/0,O=1/0,x=-1/0;for(const m of v){const w=[m[0]-g[0]*t,m[1]-g[1]*t,m[2]-g[2]*t],j=w[0]*l[0]+w[1]*l[1]+w[2]*l[2],z=(w[0]*s[0]+w[1]*s[1]+w[2]*s[2])/(j*P),U=(w[0]*k[0]+w[1]*k[1]+w[2]*k[2])/(j*R);r=Math.min(r,z),f=Math.max(f,z),O=Math.min(O,U),x=Math.max(x,U)}return{x0:r,x1:f,y0:O,y1:x,half:Math.max((f-r)/2,(x-O)/2)}},C=1-2*Math.min(Math.max(u,0),.45);let S=Math.max(...v.map(t=>Math.hypot(...t)))*1.05,M=S*40;for(let t=0;t<32;t++){const r=(S+M)/2;b(r).half>C?S=r:M=r}const c=b(M);return{d:M,cx:(c.x0+c.x1)/2,cy:(c.y0+c.y1)/2,hx:(c.x1-c.x0)/2,hy:(c.y1-c.y0)/2}}function Ge(e,o){const n=[];for(const a of[e[0],o[0]])for(const i of[e[1],o[1]])for(const p of[e[2],o[2]])n.push([a,i,p]);return n}const A=document.getElementById("c"),me=new URLSearchParams(location.search),te=e=>window.webkit?.messageHandlers?.jeep?.postMessage(e),Ne={theme:"dark",lights:!1,roof:"on",doorsOff:!1,doors:{FL:!1,FR:!1,BL:!1,BR:!1},gate:!1};let E=structuredClone(Ne),D={},_=null,W=!!window.matchMedia?.("(prefers-reduced-motion: reduce)").matches,xe=0,q=!1;const G=(e,o)=>({...e,...o,...o.doors?{doors:{...e.doors,...o.doors}}:{}});function oe(){clearTimeout(xe),!(q||!_)&&(q=!0,_.setView("hero",W?1:1600))}function we(){const e=D.theme==="light"?"light":"dark";if(document.documentElement.dataset.theme=e,ae||Y(ye(G(E,D)),!1),!!_){for(const[o,...n]of ze(E,D))_[o](...n);E=G(E,D)}}const Xe=e=>e<.5?4*e*e*e:1-Math.pow(-2*e+2,3)/2;let K=0,N=0,Me=0,I=null;function X(e){K=e,_&&(_.root.rotation.y=Le.degToRad(e),I&&(I.yaw.value=_.root.rotation.y),_.kick())}function ne(){cancelAnimationFrame(N),N=0,clearTimeout(Me)}let Z=!1;function re(e,o){Z!==e&&(Z=e,_&&q&&_.setView("hero",W?1:o))}function Ze(){ne();const e=He(K);if(W||Math.abs(e)<.05){X(0),re(!1,500);return}const o=performance.now(),n=a=>{const i=Math.min(1,(a-o)/900);X(e*(1-Xe(i))),N=i<1?requestAnimationFrame(n):0,i>=1&&re(!1,500)};N=requestAnimationFrame(n)}const L=document.getElementById("strip"),Ye=document.getElementById("puck"),ee=document.getElementById("strip-label"),Je=['<rect x="7" y="13" width="18" height="26" rx="3" fill="currentColor" opacity=".9"/>','<rect x="7" y="23" width="18" height="16" rx="3" fill="currentColor" opacity=".9"/>',"",""],$e='<rect x="3" y="2" width="26" height="52" rx="9" fill="none" stroke="currentColor" stroke-width="2"/>',Ke='<path d="M3 17V11a9 9 0 0 1 9-9h8a9 9 0 0 1 9 9v6M3 41v4a9 9 0 0 0 9 9h8a9 9 0 0 0 9-9v-4" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>',Qe=e=>`<svg viewBox="0 0 32 56" aria-hidden="true">${e===3?Ke:$e}${Je[e]}<path d="M8 8h16" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>`;let pe=-1,ae=!1;function Y(e,o){const n=he.length-1,a=Math.round(Math.min(n,Math.max(0,e)));L.classList.toggle("live",o),L.style.setProperty("--pos",String(Math.min(n,Math.max(0,e))/n)),a!==pe&&(pe=a,Ye.innerHTML=Qe(a),ee.textContent=he[a].label,ee.style.marginLeft=`${-Math.max(0,ee.offsetWidth/2-(L.offsetWidth/2-2))}px`)}window.jeepEmbed={apply(e={}){D=G(D,e),typeof e.reducedMotion=="boolean"&&(W=e.reducedMotion||W,document.documentElement.classList.toggle("reduce",W),e.reducedMotion&&oe()),we()},spin(e){Number.isFinite(e)&&(ne(),oe(),re(!0,300),X(K+e))},release(){ne(),Me=setTimeout(Ze,2500)},strip(e){Number.isFinite(e)&&(ae=!0,Y(e,!0))},stripRelease(e){ae=!1,Y(Number.isFinite(e)?e:ye(G(E,D)),!1)}};Y(0,!1);const et={name:"JeepFloor",uniforms:{color:{value:null},tDiffuse:{value:null},textureMatrix:{value:null},strength:{value:.25},glow:{value:new B(.05,.052,.058)},foot:{value:new fe(1,2.4)},centre:{value:new fe(0,0)},reach:{value:.7},yaw:{value:0},light:{value:0},dayFloor:{value:new B(.86,.86,.875)},dayStrength:{value:.18}},vertexShader:`
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
    }`};function tt(e,o){const n=document.createElement("canvas");n.width=256,n.height=512;const a=n.getContext("2d"),i=70;a.shadowColor="rgba(0,0,0,1)",a.shadowBlur=46,a.shadowOffsetX=1e3,a.fillStyle="#000",a.beginPath(),a.roundRect(i-1e3,i,256-2*i,512-2*i,40),a.fill();const p=new Ie(n),u=256/(256-2*i),h=new V(new ie(e*u,o*(512/(512-2*i))),new H({map:p,color:0,transparent:!0,opacity:1,depthWrite:!1}));return h.rotation.x=-Math.PI/2,h}function ot(e){const o=new Te;o.add(new V(new We(30,32,16),new H({color:new B(.012,.012,.014),side:Be})));const n=(u,h,d,g,l,s)=>{const y=new V(new ie(u,h),new H({color:new B(...d).multiplyScalar(g),side:Ue}));y.position.set(...l),y.lookAt(...s),o.add(y)};n(1.2,11,[1,1,1],2.2,[0,8,0],[0,0,0]);for(const[u,h]of[[6.4,9],[7.6,12],[8.8,9]])n(13,.22,[1,1,1],h,[-7,u,-9],[0,1,0]);n(7,2.2,[1,1,1],.9,[7,3.5,5],[0,1,0]),n(9,.9,[.8,.88,1],1.8,[-8,1.6,-8],[0,1,0]),n(14,.8,[1,1,1],11,[-7,.7,7],[0,.7,0]);const a=new V(new Ae(7,48),new H({color:new B(1.1,1.1,1.15)}));a.rotation.x=-Math.PI/2,a.position.y=-.6,o.add(a),n(14,1.2,[1,1,1],.35,[0,1.2,12],[0,1,0]);const i=new Ee(e),p=i.fromScene(o,.03).texture;return i.dispose(),p}const ge=28,nt=.06,rt=Array.from({length:24},(e,o)=>o*15);let J=null,se=0;function at(e,o){if(!J)return null;const n=A.clientWidth,a=A.clientHeight;if(!n||!a)return null;const i=L.getBoundingClientRect().left+(L.offsetWidth-30)/2,p=e==="top"?Math.max(ge,n-i+4):ge,u=Math.max(1,n-p),h=Z&&e!=="top"?rt:[0],d=(g,l)=>{const s=qe(J,{az:g,el:l,ty:se,fovDeg:24,aspect:u/a,margin:nt,yaws:h});return{d:s.d,offset:[p/2+s.cx*u/2,-s.cy*a/2],right:u/2+s.hx*u/2}};if(e==="hero"&&!Z){const g=d(o.az,o.el).right;L.style.right=`${Math.max(0,n-(g+6+15)-22)}px`}return{...d(o.az,o.el),y:se,fitAt:d}}const F=(e,o,n)=>e+(o-e)*n;async function st(){const e=await ke(A,{url:new URL("model/jeep.glb",document.baseURI).href,onProgress:t=>te({type:"progress",value:t}),fitView:at}),o=e.root.parent;e.renderer.setClearColor(0,0),e.controls.enabled=!1,e.setNight(!1),o.environment=ot(e.renderer);const n=new Set;e.root.traverse(t=>{if(t.isMesh)for(const r of[].concat(t.material))r.name==="JMI_1355060001_004"&&n.add(r)});const a=t=>{for(const r of n)r.metalness=F(.15,.55,t),r.roughness=F(.1,.2,t),r.isMeshPhysicalMaterial&&(r.clearcoat=F(1,0,t),r.clearcoatRoughness=.04)},i=new Q;e.root.traverse(t=>{t.isMesh&&t.castShadow&&i.union(new Q().setFromObject(t))});const p=i.getSize(new T),u=i.getCenter(new T),h=new $(new ie(24,24),{textureWidth:1024,textureHeight:1024,color:16777215,clipBias:.002,shader:et});h.rotation.x=-Math.PI/2,h.position.y=4e-4,Object.assign(h.material,{transparent:!0,depthWrite:!1,blending:Pe,blendSrc:ue,blendDst:de,blendSrcAlpha:ue,blendDstAlpha:de}),h.renderOrder=1,o.add(h),I=h.material.uniforms,I.foot.value.set(p.x/2,p.z/2),I.centre.value.set(u.x,u.z),I.reach.value=p.y*.35,o.traverse(t=>{t.isMesh&&t.material?.type==="ShadowMaterial"&&(t.position.y=.003,t.material.opacity=.5,t.renderOrder=2)});const d=[];o.traverse(t=>{t.isMesh&&t.material?.type==="ShadowMaterial"&&d.push(t.material)});const g=tt(p.x*1.02,p.z*.98);g.position.set(u.x,.005,u.z),g.renderOrder=3,e.root.add(g),o.traverse(t=>{t.isDirectionalLight&&t.castShadow&&(t.intensity=1.1)}),e.renderer.toneMappingExposure=1.1;const l=new Ce(13623551,2.6);l.position.set(-6,2.6,-7),o.add(l);const s=new De(16777215,14211292,0);o.add(s);const y=[];o.traverse(t=>{t.isDirectionalLight&&t.castShadow&&y.push(t)});const k=[];o.traverse(t=>{t.isDirectionalLight&&!t.castShadow&&t!==l&&k.push([t,t.intensity])});let R=0,P=0;function v(t){R=t,a(t),h.material.uniforms.light.value=t,g.material.opacity=F(1,.5,t);for(const r of d)r.opacity=F(.5,.18,t);for(const r of y)r.intensity=F(1.1,2.4,t);for(const[r,f]of k)r.intensity=f*F(1,2.2,t);l.intensity=F(2.6,1.2,t),s.intensity=F(0,.9,t),o.environmentIntensity=F(1,1.5,t),e.renderer.toneMappingExposure=F(1.1,1,t),e.kick()}let b=!1;e.setTheme=t=>{const r=t==="light"?1:0,f=R;if(cancelAnimationFrame(P),!b||W){b=!0,v(r);return}const O=performance.now(),x=m=>{const w=Math.min(1,(m-O)/300);v(F(f,r,w)),P=w<1?requestAnimationFrame(x):0};P=requestAnimationFrame(x)},e.setTheme(D.theme==="light"?"light":"dark"),E.theme=D.theme==="light"?"light":"dark",b=!0,J=[],e.root.traverse(t=>{if(t.isMesh&&t.castShadow){const r=new Q().setFromObject(t);r.isEmpty()||J.push(...Ge(r.min.toArray(),r.max.toArray()))}}),se=u.y;let C="hero";const S=e.setView;e.setView=(t,r)=>{C=t,S(t,r)};const M=()=>{!A.clientWidth||!A.clientHeight||(e.cam.zoom=1,S(C,1),e.kick())};M(),new ResizeObserver(M).observe(A),_=e,X(K),we();const c=me.get("view")||"top";c==="top"&&me.get("settle")==="0"?e.setView("top",1):c==="top"&&!W?(e.setView("top",1),xe=setTimeout(oe,2400)):(q=!0,e.setView(c==="top"?"hero":c,1)),e.kick(),te({type:"ready"})}st().catch(e=>te({type:"error",message:String(e)}));
