'use strict';

/* ── Starfield ───────────────────────────────────────────────── */
(function () {
  const sf = document.getElementById('starfield');
  if (!sf) return;
  for (let i = 0; i < 180; i++) {
    const s = document.createElement('span');
    const size = Math.random() < 0.78 ? 1 : Math.random() < 0.6 ? 1.5 : 2;
    const op = (Math.random() * 0.55 + 0.15).toFixed(2);
    s.className = 'star' + (Math.random() < 0.25 ? ' star-twinkle' : '');
    s.style.cssText =
      'left:'  + (Math.random() * 100).toFixed(1) + '%;' +
      'top:'   + (Math.random() * 100).toFixed(1) + '%;' +
      'width:' + size + 'px;height:' + size + 'px;' +
      'opacity:' + op + ';' +
      (s.className.includes('twinkle')
        ? 'animation-delay:' + (Math.random() * 4).toFixed(1) + 's;' : '');
    sf.appendChild(s);
  }
})();

/* ── Active nav link ─────────────────────────────────────────── */
(function () {
  const page = window.location.pathname.split('/').pop() || 'index.html';
  document.querySelectorAll('.nav-links a').forEach(function (a) {
    const href = (a.getAttribute('href') || '').split('/').pop() || 'index.html';
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
      if (ci === phrase.length) {
        deleting = true;
        setTimeout(tick, PAUSE_END);
        return;
      }
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
  var dur = 1600;
  var startTime = performance.now();
  (function step(now) {
    var p = Math.min((now - startTime) / dur, 1);
    var eased = 1 - Math.pow(1 - p, 3);
    el.textContent = Math.floor(eased * target);
    if (p < 1) requestAnimationFrame(step);
    else el.textContent = target;
  })(startTime);
}

var counterObs = new IntersectionObserver(function (entries) {
  entries.forEach(function (e) {
    if (!e.isIntersecting) return;
    e.target.querySelectorAll('[data-target]').forEach(animateCounter);
    counterObs.unobserve(e.target);
  });
}, { threshold: 0.2 });

var statsRow = document.querySelector('.stats-row');
if (statsRow) counterObs.observe(statsRow);
