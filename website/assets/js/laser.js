/*
  Swarm Code marketing site — hero laser animation
  ==================================================

  WebGL2 vertical blue light beam / glow effect.
  Renders a glowing vertical beam in the center of the hero section.

  One canvas, requestAnimationFrame loop, respects prefers-reduced-motion.
*/

(function () {
  "use strict";

  var LASER_COLOR = [0.29, 0.55, 1.0]; // #4a8cff — Swarm Code blue

  var VERT_SRC = [
    "precision highp float;",
    "attribute vec3 position;",
    "void main() {",
    "  gl_Position = vec4(position, 1.0);",
    "}"
  ].join("\n");

  var FRAG_SRC = [
    "#ifdef GL_ES",
    "#extension GL_OES_standard_derivatives : enable",
    "#endif",
    "precision highp float;",
    "",
    "uniform float iTime;",
    "uniform vec2 iResolution;",
    "uniform vec3 uColor;",
    "",
    "#define PI 3.14159265359",
    "#define TAU 6.28318530718",
    "",
    "float hash(vec2 p) {",
    "  p = fract(p * vec2(123.34, 456.21));",
    "  p += dot(p, p + 34.123);",
    "  return fract(p.x * p.y);",
    "}",
    "",
    "float noise(vec2 p) {",
    "  vec2 i = floor(p), f = fract(p);",
    "  float a = hash(i), b = hash(i + vec2(1.0, 0.0));",
    "  float c = hash(i + vec2(0.0, 1.0)), d = hash(i + vec2(1.0, 1.0));",
    "  vec2 u = f * f * (3.0 - 2.0 * f);",
    "  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);",
    "}",
    "",
    "float fbm(vec2 p) {",
    "  float v = 0.0, a = 0.5;",
    "  mat2 rot = mat2(0.86, 0.5, -0.5, 0.86);",
    "  for (int i = 0; i < 5; i++) {",
    "    v += a * noise(p);",
    "    p = rot * p * 2.0 + 10.0;",
    "    a *= 0.5;",
    "  }",
    "  return v;",
    "}",
    "",
    "void main() {",
    "  vec2 uv = (gl_FragCoord.xy - 0.5 * iResolution) / min(iResolution.x, iResolution.y);",
    "  float t = iTime;",
    "",
    "  // --- Core beam ---",
    "  float beamX = 0.0;",
    "  float beamWidth = 0.012 + 0.004 * sin(t * 1.3);",
    "  float beam = exp(-abs(uv.x - beamX) / beamWidth);",
    "",
    "  // --- Vertical brightness variation ---",
    "  float yFade = smoothstep(-1.0, -0.3, uv.y) * smoothstep(1.0, 0.2, uv.y);",
    "  beam *= yFade;",
    "",
    "  // --- Bright core ---",
    "  float coreWidth = 0.003 + 0.001 * sin(t * 2.1);",
    "  float core = exp(-abs(uv.x - beamX) / coreWidth);",
    "  core *= yFade;",
    "",
    "  // --- Horizontal glow arcs ---",
    "  float arc1 = 0.0, arc2 = 0.0;",
    "  for (int i = 0; i < 3; i++) {",
    "    float fi = float(i);",
    "    float phase = t * 0.8 + fi * 2.094;",
    "    float angle = PI * 0.5 + 0.6 * sin(phase);",
    "    float radius = 0.08 + 0.03 * sin(t * 1.1 + fi);",
    "    float arcX = beamX + cos(angle) * radius;",
    "    float arcY = sin(angle) * radius * 0.5;",
    "    float arcDist = length(vec2(uv.x - arcX, uv.y - arcY));",
    "    float arcBright = 0.003 + 0.002 * sin(t * 1.5 + fi);",
    "    float arc = exp(-arcDist / arcBright) * 0.6;",
    "    arc *= smoothstep(-0.8, -0.2, uv.y) * smoothstep(0.8, 0.0, uv.y);",
    "    if (i == 0) arc1 = arc;",
    "    else arc2 += arc * 0.5;",
    "  }",
    "",
    "  // --- Top flare ---",
    "  float flareY = smoothstep(0.4, 0.9, uv.y);",
    "  float flareX = exp(-abs(uv.x) / (0.15 + 0.05 * sin(t * 2.0)));",
    "  float flare = flareY * flareX * (0.5 + 0.3 * sin(t * 1.7)) * 0.8;",
    "",
    "  // --- Wisps (animated streaks traveling up the beam) ---",
    "  float wisps = 0.0;",
    "  for (int i = 0; i < 8; i++) {",
    "    float fi = float(i);",
    "    float seed = hash(vec2(fi, 1.0));",
    "    float speed = 0.3 + seed * 0.4;",
    "    float wY = fract(uv.y * 0.5 - t * speed + seed);",
    "    float wLen = 0.05 + 0.08 * hash(vec2(fi, 2.0));",
    "    float wYFade = smoothstep(0.0, wLen, wY) * smoothstep(wLen * 2.0, wLen, wY);",
    "    float side = mod(fi, 2.0) == 0.0 ? -1.0 : 1.0;",
    "    float wX = beamX + side * (0.02 + 0.03 * hash(vec2(fi, 3.0)));",
    "    float wDist = abs(uv.x - wX);",
    "    float wBright = 0.015 + 0.01 * sin(t * 3.0 + fi);",
    "    float w = exp(-wDist / wBright) * wYFade;",
    "    w *= yFade;",
    "    wisps += w * (0.3 + 0.7 * hash(vec2(fi, 4.0)));",
    "  }",
    "",
    "  // --- Volumetric fog ---",
    "  vec2 fogUV = vec2(uv.x * 2.0, uv.y * 1.5 + t * 0.1);",
    "  float fog = fbm(fogUV) * 0.5;",
    "  fog += fbm(fogUV * 2.0 + vec2(t * 0.05, 0.0)) * 0.25;",
    "  float fogMask = exp(-abs(uv.x) / 0.3) * yFade;",
    "  fog *= fogMask * 0.35;",
    "",
    "  // --- Combine ---",
    "  float intensity = beam * 0.6 + core * 0.8 + arc1 + arc2 + flare + wisps + fog;",
    "",
    "  // --- Edge vignette ---",
    "  float edgeFade = 1.0 - smoothstep(0.5, 1.2, length(uv));",
    "  intensity *= edgeFade;",
    "",
    "  vec3 col = uColor * intensity;",
    "  float alpha = clamp(intensity * 0.9, 0.0, 1.0);",
    "",
    "  gl_FragColor = vec4(col, alpha);",
    "}"
  ].join("\n");

  function createShader(gl, type, source) {
    var shader = gl.createShader(type);
    gl.shaderSource(shader, source);
    gl.compileShader(shader);
    if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
      console.error("Laser shader error:", gl.getShaderInfoLog(shader));
      gl.deleteShader(shader);
      return null;
    }
    return shader;
  }

  function createProgram(gl, vertSrc, fragSrc) {
    var vert = createShader(gl, gl.VERTEX_SHADER, vertSrc);
    var frag = createShader(gl, gl.FRAGMENT_SHADER, fragSrc);
    if (!vert || !frag) return null;

    var program = gl.createProgram();
    gl.attachShader(program, vert);
    gl.attachShader(program, frag);
    gl.linkProgram(program);

    if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
      console.error("Laser program link error:", gl.getProgramInfoLog(program));
      gl.deleteProgram(program);
      return null;
    }
    return program;
  }

  function initHeroLaser(host) {
    var canvas = host.querySelector("canvas");
    if (!canvas) return;

    var gl = canvas.getContext("webgl2", { alpha: true, premultipliedAlpha: false });
    if (!gl) {
      console.warn("WebGL2 not available — hero laser disabled");
      return;
    }

    var program = createProgram(gl, VERT_SRC, FRAG_SRC);
    if (!program) return;

    var posLoc = gl.getAttribLocation(program, "position");
    var iTimeLoc = gl.getUniformLocation(program, "iTime");
    var iResLoc = gl.getUniformLocation(program, "iResolution");
    var uColorLoc = gl.getUniformLocation(program, "uColor");

    var buf = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, buf);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([
      -1, -1, 0,  1, -1, 0,  -1, 1, 0,
      -1,  1, 0,  1, -1, 0,   1, 1, 0
    ]), gl.STATIC_DRAW);

    var startTime = performance.now();
    var frame = 0;
    var reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");

    function resize() {
      var rect = host.getBoundingClientRect();
      var dpr = Math.min(window.devicePixelRatio || 1, 2);
      var w = Math.max(1, Math.round(rect.width * dpr));
      var h = Math.max(1, Math.round(rect.height * dpr));
      if (canvas.width !== w || canvas.height !== h) {
        canvas.width = w;
        canvas.height = h;
        gl.viewport(0, 0, w, h);
      }
    }

    function draw() {
      frame = 0;
      resize();

      gl.useProgram(program);

      gl.bindBuffer(gl.ARRAY_BUFFER, buf);
      gl.enableVertexAttribArray(posLoc);
      gl.vertexAttribPointer(posLoc, 3, gl.FLOAT, false, 0, 0);

      var t = reducedMotion.matches ? 0 : (performance.now() - startTime) / 1000.0;
      gl.uniform1f(iTimeLoc, t);
      gl.uniform2f(iResLoc, canvas.width, canvas.height);
      gl.uniform3fv(uColorLoc, LASER_COLOR);

      gl.drawArrays(gl.TRIANGLES, 0, 6);
    }

    function tick() {
      if (frame) return;
      frame = requestAnimationFrame(tick);
      draw();
    }

    tick();

    if ("ResizeObserver" in window) {
      var ro = new ResizeObserver(function () {
        resize();
        draw();
      });
      ro.observe(host);
    } else {
      window.addEventListener("resize", function () {
        resize();
        draw();
      });
    }
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", function () {
      Array.prototype.forEach.call(
        document.querySelectorAll("[data-laser-field]"),
        initHeroLaser
      );
    });
  } else {
    Array.prototype.forEach.call(
      document.querySelectorAll("[data-laser-field]"),
      initHeroLaser
    );
  }
})();
