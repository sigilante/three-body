// Three-Body Problem Visualization
// Client-side physics simulation with beautiful particle trails

// Preset initial conditions from https://observablehq.com/@rreusser/periodic-planar-three-body-orbits
const PRESETS = {
    'figure-eight': {
        name: 'Figure-8 (Chenciner-Montgomery)',
        bodies: [
            { px: 0.97000436, py: -0.24308753, vx: 0.466203685, vy: 0.43236573, mass: 1, color: '#ff3366' },
            { px: -0.97000436, py: 0.24308753, vx: 0.466203685, vy: 0.43236573, mass: 1, color: '#33ff66' },
            { px: 0, py: 0, vx: -0.93240737, vy: -0.86473146, mass: 1, color: '#3366ff' }
        ],
        G: 1.0,
        dt: 0.001
    },
    'butterfly': {
        name: 'Butterfly',
        bodies: [
            { px: 0.306893, py: 0.125507, vx: 0.080584, vy: 0.588836, mass: 1, color: '#ff3366' },
            { px: -0.306893, py: -0.125507, vx: 0.080584, vy: 0.588836, mass: 1, color: '#33ff66' },
            { px: 0, py: 0, vx: -0.161168, vy: -1.177672, mass: 1, color: '#3366ff' }
        ],
        G: 1.0,
        dt: 0.001
    },
    'moth': {
        name: 'Moth I',
        bodies: [
            { px: 0.464445, py: 0.396060, vx: 0.079766, vy: 0.588836, mass: 1, color: '#ff3366' },
            { px: -0.464445, py: -0.396060, vx: 0.079766, vy: 0.588836, mass: 1, color: '#33ff66' },
            { px: 0, py: 0, vx: -0.159532, vy: -1.177672, mass: 1, color: '#3366ff' }
        ],
        G: 1.0,
        dt: 0.001
    },
    'dragonfly': {
        name: 'Dragonfly',
        bodies: [
            { px: 1.04987, py: 0, vx: 0, vy: 0.736915, mass: 1, color: '#ff3366' },
            { px: -1.04987, py: 0, vx: 0, vy: 0.736915, mass: 1, color: '#33ff66' },
            { px: 0, py: 0, vx: 0, vy: -1.47383, mass: 1, color: '#3366ff' }
        ],
        G: 1.0,
        dt: 0.001
    },
    'yarn': {
        name: 'Yarn',
        bodies: [
            { px: 0.558287, py: 0.349769, vx: 0.343127, vy: 0.663582, mass: 1, color: '#ff3366' },
            { px: -0.558287, py: -0.349769, vx: 0.343127, vy: 0.663582, mass: 1, color: '#33ff66' },
            { px: 0, py: 0, vx: -0.686254, vy: -1.327164, mass: 1, color: '#3366ff' }
        ],
        G: 1.0,
        dt: 0.001
    },
    'goggles': {
        name: 'Goggles',
        bodies: [
            { px: 0.347111, py: 0.532728, vx: 0.398905, vy: 0.039998, mass: 1, color: '#ff3366' },
            { px: -0.347111, py: -0.532728, vx: 0.398905, vy: 0.039998, mass: 1, color: '#33ff66' },
            { px: 0, py: 0, vx: -0.79781, vy: -0.079996, mass: 1, color: '#3366ff' }
        ],
        G: 1.0,
        dt: 0.001
    }
};

class ThreeBodySimulation {
    constructor(canvasId) {
        this.canvas = document.getElementById(canvasId);
        this.ctx = this.canvas.getContext('2d');
        this.setupCanvas();

        // Simulation state
        this.bodies = [];
        this.trails = [[], [], []];
        this.maxTrailLength = 500;
        this.time = 0;
        this.stepCount = 0;
        this.isRunning = false;
        this.speed = 1.0;

        // Physics parameters
        this.G = 1.0;
        this.dt = 0.001;
        this.softening = 0.01;  // Prevents singularities

        // Session info
        this.sessionId = null;
        this.sessionStatus = 'Not started';

        // Animation
        this.animationId = null;
        this.stepsPerFrame = 10;  // Run multiple physics steps per render frame

        this.setupEventListeners();
        this.loadPreset('figure-eight');
    }

    setupCanvas() {
        // Set canvas size
        const container = this.canvas.parentElement;
        this.canvas.width = container.clientWidth;
        this.canvas.height = container.clientHeight;

        // Calculate scale and offset for coordinate transformation
        this.scale = Math.min(this.canvas.width, this.canvas.height) * 0.25;
        this.centerX = this.canvas.width / 2;
        this.centerY = this.canvas.height / 2;

        // Handle window resize
        window.addEventListener('resize', () => {
            this.canvas.width = container.clientWidth;
            this.canvas.height = container.clientHeight;
            this.scale = Math.min(this.canvas.width, this.canvas.height) * 0.25;
            this.centerX = this.canvas.width / 2;
            this.centerY = this.canvas.height / 2;
        });
    }

    setupEventListeners() {
        document.getElementById('play-btn').addEventListener('click', () => this.play());
        document.getElementById('pause-btn').addEventListener('click', () => this.pause());
        document.getElementById('reset-btn').addEventListener('click', () => this.reset());

        const speedSlider = document.getElementById('speed-slider');
        speedSlider.addEventListener('input', (e) => {
            this.speed = parseFloat(e.target.value);
            document.getElementById('speed-value').textContent = `${this.speed.toFixed(1)}x`;
        });

        document.getElementById('load-preset-btn').addEventListener('click', () => {
            const presetId = document.getElementById('preset-select').value;
            if (presetId !== 'custom') {
                this.loadPreset(presetId);
            }
        });

        document.getElementById('apply-config-btn').addEventListener('click', () => {
            this.applyCustomConfig();
        });

        document.getElementById('save-state-btn').addEventListener('click', () => {
            this.saveState();
        });
    }

    loadPreset(presetId) {
        const preset = PRESETS[presetId];
        if (!preset) return;

        this.pause();
        this.bodies = preset.bodies.map(b => ({
            pos: { x: b.px, y: b.py },
            vel: { x: b.vx, y: b.vy },
            mass: b.mass,
            color: b.color
        }));

        this.G = preset.G;
        this.dt = preset.dt;
        this.time = 0;
        this.stepCount = 0;
        this.trails = [[], [], []];

        // Update input fields
        this.updateInputFields();
        this.render();
    }

    updateInputFields() {
        const inputs = document.querySelectorAll('#body-configs input[type="number"]');
        inputs.forEach(input => {
            const bodyIdx = parseInt(input.dataset.body);
            const prop = input.dataset.prop;
            const body = this.bodies[bodyIdx];

            if (!body) return;

            switch(prop) {
                case 'px': input.value = body.pos.x.toFixed(2); break;
                case 'py': input.value = body.pos.y.toFixed(2); break;
                case 'vx': input.value = body.vel.x.toFixed(2); break;
                case 'vy': input.value = body.vel.y.toFixed(2); break;
            }
        });
    }

    applyCustomConfig() {
        const inputs = document.querySelectorAll('#body-configs input[type="number"]');
        const newBodies = [
            { pos: {x: 0, y: 0}, vel: {x: 0, y: 0}, mass: 1, color: '#ff3366' },
            { pos: {x: 0, y: 0}, vel: {x: 0, y: 0}, mass: 1, color: '#33ff66' },
            { pos: {x: 0, y: 0}, vel: {x: 0, y: 0}, mass: 1, color: '#3366ff' }
        ];

        inputs.forEach(input => {
            const bodyIdx = parseInt(input.dataset.body);
            const prop = input.dataset.prop;
            const value = parseFloat(input.value);

            switch(prop) {
                case 'px': newBodies[bodyIdx].pos.x = value; break;
                case 'py': newBodies[bodyIdx].pos.y = value; break;
                case 'vx': newBodies[bodyIdx].vel.x = value; break;
                case 'vy': newBodies[bodyIdx].vel.y = value; break;
            }
        });

        this.pause();
        this.bodies = newBodies;
        this.time = 0;
        this.stepCount = 0;
        this.trails = [[], [], []];
        this.render();
    }

    // Vector operations
    vecAdd(a, b) {
        return { x: a.x + b.x, y: a.y + b.y };
    }

    vecSub(a, b) {
        return { x: a.x - b.x, y: a.y - b.y };
    }

    vecMul(v, s) {
        return { x: v.x * s, y: v.y * s };
    }

    vecMag(v) {
        return Math.sqrt(v.x * v.x + v.y * v.y);
    }

    // Calculate acceleration on body i due to body j
    calcAcceleration(i, j) {
        const r = this.vecSub(this.bodies[j].pos, this.bodies[i].pos);
        const distSq = r.x * r.x + r.y * r.y;
        const softenedDistSq = distSq + this.softening * this.softening;
        const dist = Math.sqrt(softenedDistSq);

        const forceMag = this.G * this.bodies[j].mass / softenedDistSq;
        const dir = this.vecMul(r, 1 / dist);

        return this.vecMul(dir, forceMag);
    }

    // Euler integration step
    eulerStep() {
        // Calculate accelerations for all bodies
        const accelerations = this.bodies.map((_, i) => {
            let acc = { x: 0, y: 0 };
            for (let j = 0; j < this.bodies.length; j++) {
                if (i !== j) {
                    const a = this.calcAcceleration(i, j);
                    acc = this.vecAdd(acc, a);
                }
            }
            return acc;
        });

        // Update velocities and positions
        this.bodies.forEach((body, i) => {
            body.vel = this.vecAdd(body.vel, this.vecMul(accelerations[i], this.dt));
            body.pos = this.vecAdd(body.pos, this.vecMul(body.vel, this.dt));

            // Add to trail
            this.trails[i].push({ x: body.pos.x, y: body.pos.y });
            if (this.trails[i].length > this.maxTrailLength) {
                this.trails[i].shift();
            }
        });

        this.time += this.dt;
        this.stepCount++;
    }

    // Convert simulation coordinates to canvas coordinates
    simToCanvas(pos) {
        return {
            x: this.centerX + pos.x * this.scale,
            y: this.centerY - pos.y * this.scale  // Flip Y axis
        };
    }

    // Render the simulation
    render() {
        const ctx = this.ctx;

        // Clear canvas with fade effect
        ctx.fillStyle = 'rgba(10, 14, 39, 0.1)';
        ctx.fillRect(0, 0, this.canvas.width, this.canvas.height);

        // Draw trails
        this.trails.forEach((trail, i) => {
            if (trail.length < 2) return;

            const color = this.bodies[i].color;
            const gradient = ctx.createLinearGradient(0, 0, this.canvas.width, this.canvas.height);

            ctx.beginPath();
            trail.forEach((pos, j) => {
                const canvasPos = this.simToCanvas(pos);
                if (j === 0) {
                    ctx.moveTo(canvasPos.x, canvasPos.y);
                } else {
                    ctx.lineTo(canvasPos.x, canvasPos.y);
                }
            });

            // Trail opacity fades from back to front
            const alpha = 0.3;
            ctx.strokeStyle = color + Math.floor(alpha * 255).toString(16).padStart(2, '0');
            ctx.lineWidth = 2;
            ctx.stroke();
        });

        // Draw bodies with glow effect
        this.bodies.forEach((body, i) => {
            const canvasPos = this.simToCanvas(body.pos);

            // Glow
            const gradient = ctx.createRadialGradient(
                canvasPos.x, canvasPos.y, 0,
                canvasPos.x, canvasPos.y, 20
            );
            gradient.addColorStop(0, body.color + 'ff');
            gradient.addColorStop(0.5, body.color + '88');
            gradient.addColorStop(1, body.color + '00');

            ctx.fillStyle = gradient;
            ctx.beginPath();
            ctx.arc(canvasPos.x, canvasPos.y, 20, 0, Math.PI * 2);
            ctx.fill();

            // Core
            ctx.fillStyle = body.color;
            ctx.beginPath();
            ctx.arc(canvasPos.x, canvasPos.y, 6, 0, Math.PI * 2);
            ctx.fill();
        });

        // Update UI
        document.getElementById('time-display').textContent = `Time: ${this.time.toFixed(2)}`;
        document.getElementById('step-display').textContent = `Steps: ${this.stepCount}`;
    }

    // Animation loop
    animate() {
        if (!this.isRunning) return;

        // Run multiple physics steps per frame for speed
        const stepsThisFrame = Math.floor(this.stepsPerFrame * this.speed);
        for (let i = 0; i < stepsThisFrame; i++) {
            this.eulerStep();
        }

        this.render();
        this.animationId = requestAnimationFrame(() => this.animate());
    }

    play() {
        if (this.isRunning) return;
        this.isRunning = true;
        this.sessionStatus = 'active';
        document.getElementById('session-status').textContent = 'Running';
        this.animate();
    }

    pause() {
        this.isRunning = false;
        this.sessionStatus = 'paused';
        document.getElementById('session-status').textContent = 'Paused';
        if (this.animationId) {
            cancelAnimationFrame(this.animationId);
            this.animationId = null;
        }
    }

    reset() {
        this.pause();
        const presetId = document.getElementById('preset-select').value;
        if (presetId !== 'custom') {
            this.loadPreset(presetId);
        } else {
            this.time = 0;
            this.stepCount = 0;
            this.trails = [[], [], []];
            this.applyCustomConfig();
        }
    }

    // Save state to server
    async saveState() {
        try {
            const stateData = {
                bodies: this.bodies,
                time: this.time,
                stepCount: this.stepCount,
                G: this.G,
                dt: this.dt
            };

            // TODO: Implement server API call
            // For now, just log to console and save to localStorage
            console.log('Saving state:', stateData);
            localStorage.setItem('three-body-state', JSON.stringify(stateData));

            // Generate session ID if we don't have one
            if (!this.sessionId) {
                this.sessionId = this.generateUUID();
                document.getElementById('session-id').textContent = this.sessionId;
            }

            alert('State saved successfully!');
        } catch (error) {
            console.error('Error saving state:', error);
            alert('Failed to save state');
        }
    }

    generateUUID() {
        return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function(c) {
            const r = Math.random() * 16 | 0;
            const v = c === 'x' ? r : (r & 0x3 | 0x8);
            return v.toString(16);
        });
    }
}

// Initialize simulation when page loads
let simulation;
document.addEventListener('DOMContentLoaded', () => {
    simulation = new ThreeBodySimulation('simulation-canvas');
});
