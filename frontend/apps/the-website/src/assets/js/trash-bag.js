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
  // Re-enable fog for depth
  scene.fog = new THREE.FogExp2(0x0f0c29, 0.002);

  // Camera
  const camera = new THREE.PerspectiveCamera(75, window.innerWidth / window.innerHeight, 0.1, 1000);
  camera.position.z = 30;

  // Renderer
  // Revert to previous settings that looked good
  const renderer = new THREE.WebGLRenderer({ alpha: true, antialias: true });
  renderer.setSize(window.innerWidth, window.innerHeight);
  renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
  container.appendChild(renderer.domElement);

  // --- Particles ---
  const isMobile = window.innerWidth < 768;
  // Reduce count significantly for mobile to rule out performance limits
  const particleCount = isMobile ? 600 : 3000;
  
  const geometry = new THREE.BufferGeometry();
  const positions = new Float32Array(particleCount * 3);
  const colors = new Float32Array(particleCount * 3);

  const color1 = new THREE.Color(0x8b5cf6); // Purple
  const color2 = new THREE.Color(0xec4899); // Pink
  const color3 = new THREE.Color(0x06b6d4); // Cyan

  for (let i = 0; i < particleCount; i++) {
    const r = 40 * Math.cbrt(Math.random());
    const theta = Math.random() * 2 * Math.PI;
    const phi = Math.acos(2 * Math.random() - 1);

    const x = r * Math.sin(phi) * Math.cos(theta);
    const y = r * Math.sin(phi) * Math.sin(theta);
    const z = r * Math.cos(phi);

    positions[i * 3] = x;
    positions[i * 3 + 1] = y;
    positions[i * 3 + 2] = z;

    const mixedColor = color1.clone();
    if (Math.random() > 0.5) {
        mixedColor.lerp(color2, Math.random());
    } else {
        mixedColor.lerp(color3, Math.random() * 0.5);
    }

    colors[i * 3] = mixedColor.r;
    colors[i * 3 + 1] = mixedColor.g;
    colors[i * 3 + 2] = mixedColor.b;
  }

  geometry.setAttribute('position', new THREE.BufferAttribute(positions, 3));
  geometry.setAttribute('color', new THREE.BufferAttribute(colors, 3));

  // Revert to the soft glow texture
  const getTexture = () => {
      const canvas = document.createElement('canvas');
      canvas.width = 32;
      canvas.height = 32;
      const context = canvas.getContext('2d');
      const gradient = context.createRadialGradient(16, 16, 0, 16, 16, 16);
      gradient.addColorStop(0, 'rgba(255,255,255,1)');
      gradient.addColorStop(0.2, 'rgba(255,255,255,0.8)');
      gradient.addColorStop(0.5, 'rgba(255,255,255,0.2)');
      gradient.addColorStop(1, 'rgba(0,0,0,0)');
      context.fillStyle = gradient;
      context.fillRect(0, 0, 32, 32);
      const texture = new THREE.Texture(canvas);
      texture.needsUpdate = true;
      return texture;
  };

  const material = new THREE.PointsMaterial({
    size: isMobile ? 0.8 : 0.5, // Back to smaller, nicer size
    map: getTexture(),
    vertexColors: true,
    transparent: true,
    opacity: 0.8,
    depthWrite: false,
    blending: THREE.AdditiveBlending, // Back to additive for the glow
    sizeAttenuation: true
  });

  const particles = new THREE.Points(geometry, material);
  scene.add(particles);

  // --- Mouse Interaction (Physics-based) ---
  let mouseX = 0;
  let mouseY = 0;
  
  // Velocity
  let velX = 0;
  let velY = 0;
  
  // Friction (how fast it slows down)
  const friction = 0.95;
  
  // Sensitivity (how much mouse movement adds to speed)
  const sensitivity = 0.0001;

  let lastMouseX = 0;
  let lastMouseY = 0;

  const windowHalfX = window.innerWidth / 2;
  const windowHalfY = window.innerHeight / 2;

  document.addEventListener('mousemove', (event) => {
    // Calculate delta (change in position)
    const deltaX = event.clientX - lastMouseX;
    const deltaY = event.clientY - lastMouseY;
    
    // Add to velocity based on movement speed
    velY += deltaX * sensitivity; // Horizontal mouse moves Y rotation
    velX += deltaY * sensitivity; // Vertical mouse moves X rotation

    lastMouseX = event.clientX;
    lastMouseY = event.clientY;
  }, { passive: true });

  // Animation
  function animate() {
    requestAnimationFrame(animate);

    // Apply velocity
    particles.rotation.y += velY;
    particles.rotation.x += velX;

    // Apply friction (slow down)
    velX *= friction;
    velY *= friction;

    // Add a tiny bit of base rotation so it's never 100% static
    particles.rotation.y += 0.001;

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
