'use strict';

/* ── Flying Star Canvas ─────────────────────────────────────── */
(function () {
  var canvas = document.getElementById('starfield-canvas');
  if (!canvas) return;
  var ctx = canvas.getContext('2d');
  var W, H, stars = [], shooters = [], shootTimer = 0;

  function resize() {
    W = canvas.width  = window.innerWidth;
    H = canvas.height = window.innerHeight;
  }

  function mkStar(initY) {
    var t = Math.random();
    var layer = t < 0.55 ? 0 : t < 0.85 ? 1 : 2;
    var sizes  = [0.3 + Math.random() * 0.5,  0.7 + Math.random() * 0.7,  1.1 + Math.random() * 1.1];
    var speeds = [0.06 + Math.random() * 0.12, 0.16 + Math.random() * 0.22, 0.38 + Math.random() * 0.48];
    var opacs  = [0.12 + Math.random() * 0.28, 0.30 + Math.random() * 0.35, 0.50 + Math.random() * 0.50];
    return {
      x: Math.random() * W,
      y: initY ? Math.random() * H : -4,
      r: sizes[layer],
      speed: speeds[layer],
      baseOp: opacs[layer],
      phase: Math.random() * 6.28,
      phaseSpeed: 0.006 + Math.random() * 0.018,
      dx: (Math.random() - 0.5) * 0.07
    };
  }

  function mkShooter() {
    var ang = 0.30 + Math.random() * 0.40;
    var spd = 8 + Math.random() * 14;
    return {
      x: -60 + Math.random() * W * 0.55,
      y: Math.random() * H * 0.50,
      vx: Math.cos(ang) * spd,
      vy: Math.sin(ang) * spd,
      tail: 65 + Math.random() * 120,
      life: 1.0,
      fade: 0.011 + Math.random() * 0.011
    };
  }

  function init() {
    stars = [];
    for (var i = 0; i < 240; i++) stars.push(mkStar(true));
  }

  function tick() {
    var i, s, sh;
    for (i = 0; i < stars.length; i++) {
      s = stars[i];
      s.y += s.speed; s.x += s.dx; s.phase += s.phaseSpeed;
      if (s.y > H + 4) { s.y = -4; s.x = Math.random() * W; }
      if (s.x < -4)    s.x = W + 4;
      if (s.x > W + 4) s.x = -4;
    }
    for (i = shooters.length - 1; i >= 0; i--) {
      sh = shooters[i];
      sh.x += sh.vx; sh.y += sh.vy; sh.life -= sh.fade;
      if (sh.life <= 0 || sh.x > W + 80 || sh.y > H + 80) shooters.splice(i, 1);
    }
    if (++shootTimer > 160 + (Math.random() * 380 | 0)) {
      if (shooters.length < 2) shooters.push(mkShooter());
      shootTimer = 0;
    }
  }

  function render() {
    ctx.clearRect(0, 0, W, H);

    for (var i = 0; i < stars.length; i++) {
      var s = stars[i];
      ctx.globalAlpha = s.baseOp * (0.55 + 0.45 * Math.sin(s.phase));
      ctx.fillStyle = '#ffffff';
      ctx.beginPath();
      ctx.arc(s.x, s.y, s.r, 0, 6.2832);
      ctx.fill();
    }

    for (var j = 0; j < shooters.length; j++) {
      var sh = shooters[j];
      var mag = Math.sqrt(sh.vx * sh.vx + sh.vy * sh.vy);
      var tx  = sh.x - (sh.vx / mag) * sh.tail;
      var ty  = sh.y - (sh.vy / mag) * sh.tail;
      var gr  = ctx.createLinearGradient(tx, ty, sh.x, sh.y);
      gr.addColorStop(0, 'rgba(200,230,255,0)');
      gr.addColorStop(0.7, 'rgba(220,245,255,' + (sh.life * 0.5).toFixed(2) + ')');
      gr.addColorStop(1,   'rgba(255,255,255,' + (sh.life * 0.95).toFixed(2) + ')');
      ctx.globalAlpha = sh.life;
      ctx.strokeStyle = gr;
      ctx.lineWidth   = 1.8 * sh.life;
      ctx.lineCap     = 'round';
      ctx.beginPath();
      ctx.moveTo(tx, ty);
      ctx.lineTo(sh.x, sh.y);
      ctx.stroke();
    }

    ctx.globalAlpha = 1;
  }

  function loop() { tick(); render(); requestAnimationFrame(loop); }

  resize(); init(); loop();
  window.addEventListener('resize', function () { resize(); init(); }, { passive: true });
})();

/* ── Active nav link ─────────────────────────────────────────── */
(function () {
  var page = window.location.pathname.split('/').pop() || 'index.html';
  document.querySelectorAll('.nav-links a').forEach(function (a) {
    var href = (a.getAttribute('href') || '').split('/').pop() || 'index.html';
    if (href === page) a.classList.add('active');
  });
})();

/* ── Mobile nav toggle ───────────────────────────────────────── */
var navToggle = document.getElementById('nav-toggle');
var navLinks  = document.getElementById('nav-links');
if (navToggle && navLinks) {
  navToggle.addEventListener('click', function () {
    navLinks.classList.toggle('open');
    navToggle.setAttribute('aria-expanded', navLinks.classList.contains('open'));
  });
  navLinks.querySelectorAll('a').forEach(function (a) {
    a.addEventListener('click', function () { navLinks.classList.remove('open'); });
  });
}

/* ── Typewriter (home page only) ─────────────────────────────── */
(function () {
  var el = document.getElementById('type-text');
  if (!el) return;
  var phrases = [
    'Cloud Security Engineer',
    'AWS Security Architect',
    'Terraform IaC Developer',
    'DevSecOps Practitioner',
  ];
  var pi = 0, ci = 0, deleting = false;
  var PAUSE_END = 1800, PAUSE_START = 320, TYPE_MS = 72, DEL_MS = 38;

  function tick() {
    var phrase = phrases[pi];
    if (deleting) {
      el.textContent = phrase.slice(0, --ci);
      if (ci === 0) {
        deleting = false;
        pi = (pi + 1) % phrases.length;
        setTimeout(tick, PAUSE_START);
        return;
      }
      setTimeout(tick, DEL_MS);
    } else {
      el.textContent = phrase.slice(0, ++ci);
      if (ci === phrase.length) { deleting = true; setTimeout(tick, PAUSE_END); return; }
      setTimeout(tick, TYPE_MS);
    }
  }
  setTimeout(tick, 700);
})();

/* ── Ticker (home page only) ─────────────────────────────────── */
(function () {
  var track = document.getElementById('ticker-track');
  if (!track) return;
  var skills = [
    'AWS Security', 'Terraform', 'GuardDuty', 'IAM', 'Lambda',
    'Python', 'DevSecOps', 'Threat Detection', 'VPC', 'WAFv2',
    'Macie', 'Inspector v2', 'CloudTrail', 'EventBridge', 'KMS',
    'Incident Response', 'moto Testing', 'Defense in Depth',
  ];
  var double = skills.concat(skills);
  track.innerHTML = double.map(function (s) {
    return '<span class="ticker-item"><span class="dot"></span>' + s + '</span>';
  }).join('');
})();

/* ── Profile photo ───────────────────────────────────────────── */
(function () {
  var img = document.getElementById('profile-img');
  var placeholder = document.getElementById('photo-placeholder');
  if (!img || !placeholder) return;
  img.addEventListener('load', function () {
    img.classList.add('loaded');
    placeholder.style.display = 'none';
  });
  img.addEventListener('error', function () { img.style.display = 'none'; });
  if (img.complete && img.naturalWidth) {
    img.classList.add('loaded');
    placeholder.style.display = 'none';
  }
})();

/* ── Fade-in on scroll ───────────────────────────────────────── */
var io = new IntersectionObserver(function (entries) {
  entries.forEach(function (e) {
    if (!e.isIntersecting) return;
    e.target.classList.add('visible');
    io.unobserve(e.target);
  });
}, { threshold: 0.12 });

document.querySelectorAll('.fade-in').forEach(function (el) { io.observe(el); });

document.addEventListener('DOMContentLoaded', function () {
  document.querySelectorAll('.fade-in').forEach(function (el) {
    var r = el.getBoundingClientRect();
    if (r.top < window.innerHeight) el.classList.add('visible');
  });
});

/* ── Animated counters ───────────────────────────────────────── */
function animateCounter(el) {
  var target = parseInt(el.dataset.target, 10);
  var suffix = el.dataset.suffix || '';
  var dur = 1600;
  var startTime = null;
  function step(ts) {
    if (!startTime) startTime = ts;
    var p = Math.min((ts - startTime) / dur, 1);
    var eased = 1 - Math.pow(1 - p, 3);
    el.textContent = Math.round(eased * target) + (p >= 1 ? suffix : '');
    if (p < 1) requestAnimationFrame(step);
  }
  requestAnimationFrame(step);
}

var counterObs = new IntersectionObserver(function (entries) {
  entries.forEach(function (e) {
    if (!e.isIntersecting) return;
    animateCounter(e.target);
    counterObs.unobserve(e.target);
  });
}, { threshold: 0 });

document.querySelectorAll('[data-target]').forEach(function (el) {
  counterObs.observe(el);
});

/* ── Copy buttons (contact page) ────────────────────────────── */
document.querySelectorAll('.ci-copy').forEach(function (btn) {
  btn.addEventListener('click', function () {
    var text = btn.dataset.copy;
    if (!text) return;
    navigator.clipboard.writeText(text).then(function () {
      var orig = btn.innerHTML;
      btn.innerHTML = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><polyline points="20 6 9 17 4 12"/></svg>';
      setTimeout(function () { btn.innerHTML = orig; }, 1500);
    });
  });
});

/* ── Contact form success state ──────────────────────────────── */
(function () {
  var form = document.getElementById('contact-form');
  var success = document.getElementById('form-success');
  if (!form || !success) return;
  if (window.location.search.indexOf('success') !== -1) {
    form.hidden = true;
    success.hidden = false;
  }
  form.addEventListener('submit', function (e) {
    var btn = form.querySelector('.btn-send');
    if (btn) {
      btn.disabled = true;
      btn.textContent = 'Sending…';
    }
  });
})();

/* ── Skill bar animation ─────────────────────────────────────── */
var barObs = new IntersectionObserver(function (entries) {
  entries.forEach(function (e) {
    if (!e.isIntersecting) return;
    var pct = e.target.dataset.pct;
    if (pct) e.target.style.width = pct + '%';
    barObs.unobserve(e.target);
  });
}, { threshold: 0.1 });

document.querySelectorAll('.skill-fill').forEach(function (el) {
  barObs.observe(el);
});
