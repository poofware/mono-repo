import * as THREE from 'three';

export function initBackgroundScene() {
  const container = document.getElementById('canvas-container');
  if (!container) return;

  // Cleanup
  while (container.firstChild) {
    container.removeChild(container.firstChild);
  }

  // Scene
  const scene = new THREE.Scene();
  // Fog to fade particles in the distance for depth
  scene.fog = new THREE.FogExp2(0x0f0c29, 0.002);

  // Camera
  const camera = new THREE.PerspectiveCamera(75, window.innerWidth / window.innerHeight, 0.1, 1000);
  camera.position.z = 30;

  // Renderer
  const renderer = new THREE.WebGLRenderer({ alpha: true, antialias: true });
  renderer.setSize(window.innerWidth, window.innerHeight);
  renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
  container.appendChild(renderer.domElement);

  // --- Particles ---
  const particleCount = 3000;
  const geometry = new THREE.BufferGeometry();
  const positions = new Float32Array(particleCount * 3);
  const colors = new Float32Array(particleCount * 3);
  const sizes = new Float32Array(particleCount);

  const color1 = new THREE.Color(0x8b5cf6); // Purple
  const color2 = new THREE.Color(0xec4899); // Pink
  const color3 = new THREE.Color(0x06b6d4); // Cyan (accent)

  for (let i = 0; i < particleCount; i++) {
    // Random position in a sphere
    const r = 40 * Math.cbrt(Math.random());
    const theta = Math.random() * 2 * Math.PI;
    const phi = Math.acos(2 * Math.random() - 1);

    const x = r * Math.sin(phi) * Math.cos(theta);
    const y = r * Math.sin(phi) * Math.sin(theta);
    const z = r * Math.cos(phi);

    positions[i * 3] = x;
    positions[i * 3 + 1] = y;
    positions[i * 3 + 2] = z;

    // Color mixing
    const mixedColor = color1.clone();
    if (Math.random() > 0.5) {
        mixedColor.lerp(color2, Math.random());
    } else {
        mixedColor.lerp(color3, Math.random() * 0.5);
    }

    colors[i * 3] = mixedColor.r;
    colors[i * 3 + 1] = mixedColor.g;
    colors[i * 3 + 2] = mixedColor.b;

    // Random sizes
    sizes[i] = Math.random() * 1.5;
  }

  geometry.setAttribute('position', new THREE.BufferAttribute(positions, 3));
  geometry.setAttribute('color', new THREE.BufferAttribute(colors, 3));
  geometry.setAttribute('size', new THREE.BufferAttribute(sizes, 1));

  // Custom Shader Material for glowing dots
  const material = new THREE.ShaderMaterial({
    uniforms: {
      time: { value: 0 },
      pointTexture: { value: new THREE.TextureLoader().load('https://assets.codepen.io/127738/dotTexture.png') }
    },
    vertexShader: `
      attribute float size;
      varying vec3 vColor;
      uniform float time;
      void main() {
        vColor = color;
        vec3 pos = position;
        
        // Gentle wave movement
        pos.y += sin(time * 0.5 + position.x * 0.1) * 0.5;
        pos.x += cos(time * 0.3 + position.y * 0.1) * 0.5;

        vec4 mvPosition = modelViewMatrix * vec4(pos, 1.0);
        gl_PointSize = size * (300.0 / -mvPosition.z);
        gl_Position = projectionMatrix * mvPosition;
      }
    `,
    fragmentShader: `
      varying vec3 vColor;
      void main() {
        // Circular particle
        float r = distance(gl_PointCoord, vec2(0.5));
        if (r > 0.5) discard;
        
        // Soft edge glow
        float glow = 1.0 - (r * 2.0);
        glow = pow(glow, 1.5);

        gl_FragColor = vec4(vColor, glow);
      }
    `,
    blending: THREE.AdditiveBlending,
    depthTest: false,
    transparent: true,
    vertexColors: true
  });

  const particles = new THREE.Points(geometry, material);
  scene.add(particles);

  // --- Mouse Interaction ---
  let mouseX = 0;
  let mouseY = 0;
  let targetRotationX = 0;
  let targetRotationY = 0;

  const windowHalfX = window.innerWidth / 2;
  const windowHalfY = window.innerHeight / 2;

  document.addEventListener('mousemove', (event) => {
    mouseX = (event.clientX - windowHalfX) * 0.001;
    mouseY = (event.clientY - windowHalfY) * 0.001;
  });

  // Animation
  const clock = new THREE.Clock();

  function animate() {
    requestAnimationFrame(animate);
    const elapsedTime = clock.getElapsedTime();

    material.uniforms.time.value = elapsedTime;

    // Smooth rotation following mouse
    targetRotationY += (mouseX - targetRotationY) * 0.05;
    targetRotationX += (mouseY - targetRotationX) * 0.05;

    particles.rotation.y += 0.002 + targetRotationY * 0.1;
    particles.rotation.x += targetRotationX * 0.1;

    renderer.render(scene, camera);
  }

  animate();

  // Resize
  window.addEventListener('resize', () => {
    camera.aspect = window.innerWidth / window.innerHeight;
    camera.updateProjectionMatrix();
    renderer.setSize(window.innerWidth, window.innerHeight);
  });
}
