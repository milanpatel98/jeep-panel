import{M as R,P as ee,C as w,a as te,V as v,W as oe,H as re,S as ae,U as ne,b as A,c as E,d as se,B as H,e as L,f as ie,O as I,g as G,h as le,D as ce,i as de,j as ue,k as O,l as fe,m as pe,n as me,o as he,p as ge}from"./jeep-BOOcakDp.js";class W extends R{constructor(t,o={}){super(t),this.isReflector=!0,this.type="Reflector",this.camera=new ee;const r=this,n=o.color!==void 0?new w(o.color):new w(8355711),c=o.textureWidth||512,f=o.textureHeight||512,p=o.clipBias||0,l=o.shader||W.ReflectorShader,a=o.multisample!==void 0?o.multisample:4,g=new te,m=new v,d=new v,B=new v,x=new A,F=new v(0,0,-1),h=new E,b=new v,_=new v,y=new E,M=new A,i=this.camera,D=new oe(c,f,{samples:a,type:re}),C=new ae({name:l.name!==void 0?l.name:"unspecified",uniforms:ne.clone(l.uniforms),fragmentShader:l.fragmentShader,vertexShader:l.vertexShader});C.uniforms.tDiffuse.value=D.texture,C.uniforms.color.value=n,C.uniforms.textureMatrix.value=M,this.material=C,this.onBeforeRender=function(s,K,S){if(d.setFromMatrixPosition(r.matrixWorld),B.setFromMatrixPosition(S.matrixWorld),x.extractRotation(r.matrixWorld),m.set(0,0,1),m.applyMatrix4(x),b.subVectors(d,B),b.dot(m)>0)return;b.reflect(m).negate(),b.add(d),x.extractRotation(S.matrixWorld),F.set(0,0,-1),F.applyMatrix4(x),F.add(B),_.subVectors(d,F),_.reflect(m).negate(),_.add(d),i.position.copy(b),i.up.set(0,1,0),i.up.applyMatrix4(x),i.up.reflect(m),i.lookAt(_),i.far=S.far,i.updateMatrixWorld(),i.projectionMatrix.copy(S.projectionMatrix),M.set(.5,0,0,.5,0,.5,0,.5,0,0,.5,.5,0,0,0,1),M.multiply(i.projectionMatrix),M.multiply(i.matrixWorldInverse),M.multiply(r.matrixWorld),g.setFromNormalAndCoplanarPoint(m,d),g.applyMatrix4(i.matrixWorldInverse),h.set(g.normal.x,g.normal.y,g.normal.z,g.constant);const u=i.projectionMatrix;y.x=(Math.sign(h.x)+u.elements[8])/u.elements[0],y.y=(Math.sign(h.y)+u.elements[9])/u.elements[5],y.z=-1,y.w=(1+u.elements[10])/u.elements[14],h.multiplyScalar(2/h.dot(y)),u.elements[2]=h.x,u.elements[6]=h.y,u.elements[10]=h.z+1-p,u.elements[14]=h.w,r.visible=!1;const Y=s.getRenderTarget(),Q=s.xr.enabled,$=s.shadowMap.autoUpdate;s.xr.enabled=!1,s.shadowMap.autoUpdate=!1,s.setRenderTarget(D),s.state.buffers.depth.setMask(!0),s.autoClear===!1&&s.clear(),s.render(K,i),s.xr.enabled=Q,s.shadowMap.autoUpdate=$,s.setRenderTarget(Y);const z=S.viewport;z!==void 0&&s.state.viewport(z),r.visible=!0},this.getRenderTarget=function(){return D},this.dispose=function(){D.dispose(),r.material.dispose()}}}W.ReflectorShader={name:"ReflectorShader",uniforms:{color:{value:null},tDiffuse:{value:null},textureMatrix:{value:null}},vertexShader:`
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

		}`};const ve=["on","panels","off"],we=["FL","FR","BL","BR"];function xe(e={},t={}){const o=[];if(typeof t.lights=="boolean"&&t.lights!==!!e.lights&&o.push(["setLights",t.lights]),ve.includes(t.roof)&&t.roof!==(e.roof??"on")&&o.push(["setRoof",t.roof]),t.doors)for(const r of we){const n=t.doors[r];typeof n=="boolean"&&n!==!!e.doors?.[r]&&o.push(["setDoor",r,n])}return typeof t.gate=="boolean"&&t.gate!==!!e.gate&&o.push(["setGate",t.gate]),o}const be=document.getElementById("c"),X=new URLSearchParams(location.search),T=e=>window.webkit?.messageHandlers?.jeep?.postMessage(e),ye={lights:!1,roof:"on",doors:{FL:!1,FR:!1,BL:!1,BR:!1},gate:!1};let k=structuredClone(ye),U={},P=null,j=!!window.matchMedia?.("(prefers-reduced-motion: reduce)").matches,Z=0,V=!1;const J=(e,t)=>({...e,...t,...t.doors?{doors:{...e.doors,...t.doors}}:{}});function N(){clearTimeout(Z),!(V||!P)&&(V=!0,P.setView("hero",j?1:1600))}function q(){if(P){for(const[e,...t]of xe(k,U))P[e](...t);k=J(k,U)}}window.jeepEmbed={apply(e={}){U=J(U,e),typeof e.reducedMotion=="boolean"&&(j=e.reducedMotion||j,e.reducedMotion&&N()),q()}};const Me={name:"JeepFloor",uniforms:{color:{value:null},tDiffuse:{value:null},textureMatrix:{value:null},strength:{value:.3},glow:{value:new w(.08,.083,.09)},radius:{value:new ie(2.7,4)}},vertexShader:`
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
    varying vec4 vUv;
    varying vec2 vXZ;
    #include <logdepthbuf_pars_fragment>
    void main() {
      #include <logdepthbuf_fragment>
      float r = length(vXZ / radius);
      float fade = 1.0 - smoothstep(0.35, 1.0, r);   // reflection dies off near the car
      float pool = 1.0 - smoothstep(0.0, 1.05, r);   // the light pool reaches a little further
      vec3 refl = texture2DProj(tDiffuse, vUv).rgb;
      refl = mix(refl, vec3(dot(refl, vec3(0.2126, 0.7152, 0.0722))), 0.85);  // a near-neutral reflection: no beige chassis showing
      refl *= color * strength * fade * fade;
      gl_FragColor = vec4(refl + glow * pool * pool, 1.0);
      #include <tonemapping_fragment>
      #include <colorspace_fragment>
      // premultiplied: on a black page this is exactly the colour above; on anything else the floor is a dark glaze
      gl_FragColor.a = pool;
    }`};function Se(e,t){const o=document.createElement("canvas");o.width=256,o.height=512;const r=o.getContext("2d"),n=70;r.shadowColor="rgba(0,0,0,1)",r.shadowBlur=46,r.shadowOffsetX=1e3,r.fillStyle="#000",r.beginPath(),r.roundRect(n-1e3,n,256-2*n,512-2*n,40),r.fill();const c=new he(o),f=256/(256-2*n),p=new R(new L(e*f,t*(512/(512-2*n))),new O({map:c,color:0,transparent:!0,opacity:1,depthWrite:!1}));return p.rotation.x=-Math.PI/2,p}function Re(e){const t=new de;t.add(new R(new ue(30,32,16),new O({color:new w(.012,.012,.014),side:fe})));const o=(f,p,l,a,g,m)=>{const d=new R(new L(f,p),new O({color:new w(...l).multiplyScalar(a),side:ge}));d.position.set(...g),d.lookAt(...m),t.add(d)};o(2,9,[1,1,1],2.2,[0,9,0],[0,0,0]),o(7,2.2,[1,1,1],.9,[7,3.5,5],[0,1,0]),o(9,.9,[.8,.88,1],1.8,[-8,1.6,-8],[0,1,0]);const r=new R(new pe(7,48),new O({color:new w(1.1,1.1,1.15)}));r.rotation.x=-Math.PI/2,r.position.y=-.6,t.add(r),o(14,1.2,[1,1,1],.35,[0,1.2,12],[0,1,0]);const n=new me(e),c=n.fromScene(t,.03).texture;return n.dispose(),c}async function Pe(){const e=await se(be,{url:new URL("model/jeep.glb",document.baseURI).href,onProgress:a=>T({type:"progress",value:a})}),t=e.root.parent;e.renderer.setClearColor(0,0),e.controls.enabled=!1,e.setNight(!1),t.environment=Re(e.renderer);const o=new H;e.root.traverse(a=>{a.isMesh&&a.castShadow&&o.union(new H().setFromObject(a))});const r=o.getSize(new v),n=o.getCenter(new v),c=new W(new L(24,24),{textureWidth:1024,textureHeight:1024,color:16777215,clipBias:.002,shader:Me});c.rotation.x=-Math.PI/2,c.position.y=4e-4,Object.assign(c.material,{transparent:!0,depthWrite:!1,blending:le,blendSrc:G,blendDst:I,blendSrcAlpha:G,blendDstAlpha:I}),c.renderOrder=1,t.add(c),t.traverse(a=>{a.isMesh&&a.material?.type==="ShadowMaterial"&&(a.position.y=.003,a.material.opacity=.5,a.renderOrder=2)});const f=Se(r.x*1.02,r.z*.98);f.position.set(n.x,.005,n.z),f.renderOrder=3,t.add(f),t.traverse(a=>{a.isDirectionalLight&&a.castShadow&&(a.intensity=1.1)}),e.renderer.toneMappingExposure=.9;const p=new ce(13623551,2.6);p.position.set(-6,2.6,-7),t.add(p),P=e,q();const l=X.get("view")||"top";l==="top"&&X.get("settle")==="0"?e.setView("top",1):l==="top"&&!j?(e.setView("top",1),Z=setTimeout(N,2400)):(V=!0,e.setView(l==="top"?"hero":l,1)),e.kick(),T({type:"ready"})}Pe().catch(e=>T({type:"error",message:String(e)}));
