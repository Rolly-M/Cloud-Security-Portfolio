'use strict';

// ── Navigation scroll effect ────────────────────────────────
const nav = document.getElementById('nav');
window.addEventListener('scroll', () => {
  nav.classList.toggle('scrolled', window.scrollY > 20);
}, { passive: true });

// ── Mobile nav toggle ───────────────────────────────────────
const navToggle = document.getElementById('nav-toggle');
const navLinks  = document.getElementById('nav-links');

navToggle.addEventListener('click', () => {
  navLinks.classList.toggle('open');
  const isOpen = navLinks.classList.contains('open');
  navToggle.setAttribute('aria-expanded', isOpen);
});

// Close mobile nav on link click
navLinks.querySelectorAll('a').forEach(link => {
  link.addEventListener('click', () => navLinks.classList.remove('open'));
});

// ── Animated stat counters ──────────────────────────────────
function animateCounter(el) {
  const target = parseInt(el.dataset.target, 10);
  const duration = 1800;
  const startTime = performance.now();

  function step(now) {
    const elapsed = now - startTime;
    const progress = Math.min(elapsed / duration, 1);
    // Ease out cubic
    const eased = 1 - Math.pow(1 - progress, 3);
    el.textContent = Math.floor(eased * target);
    if (progress < 1) requestAnimationFrame(step);
    else el.textContent = target;
  }
  requestAnimationFrame(step);
}

// ── IntersectionObserver for fade-in + counter trigger ─────
const io = new IntersectionObserver((entries) => {
  entries.forEach(entry => {
    if (!entry.isIntersecting) return;
    entry.target.classList.add('visible');

    // Trigger counter if it's a stat number
    const counters = entry.target.querySelectorAll
      ? entry.target.querySelectorAll('[data-target]')
      : [];
    counters.forEach(animateCounter);

    io.unobserve(entry.target);
  });
}, { threshold: 0.15 });

// Observe all fade-in elements and the stats bar
document.querySelectorAll('.fade-in').forEach(el => io.observe(el));

const statsBar = document.querySelector('.stats-bar');
if (statsBar) io.observe(statsBar);

// ── Active nav link on scroll ───────────────────────────────
const sections = document.querySelectorAll('section[id]');
const navAnchors = document.querySelectorAll('.nav-links a');

window.addEventListener('scroll', () => {
  let current = '';
  sections.forEach(s => {
    if (window.scrollY >= s.offsetTop - 120) current = s.id;
  });
  navAnchors.forEach(a => {
    a.style.color = a.getAttribute('href') === '#' + current
      ? 'var(--text-primary)'
      : '';
  });
}, { passive: true });

// ── Trigger fade-in for elements already in viewport ───────
window.addEventListener('DOMContentLoaded', () => {
  document.querySelectorAll('.fade-in').forEach(el => {
    const rect = el.getBoundingClientRect();
    if (rect.top < window.innerHeight) {
      el.classList.add('visible');
    }
  });
});

// ── Modal open / close ──────────────────────────────────────
function openModal(id) {
  const overlay = document.getElementById(id);
  if (!overlay) return;
  overlay.style.display = 'flex';
  requestAnimationFrame(() => overlay.classList.add('open'));
  document.body.style.overflow = 'hidden';
  // Focus the close button for accessibility
  const closeBtn = overlay.querySelector('.modal-close');
  if (closeBtn) closeBtn.focus();
}

function closeModal(id) {
  const overlay = document.getElementById(id);
  if (!overlay) return;
  overlay.classList.remove('open');
  overlay.addEventListener('transitionend', () => {
    overlay.style.display = 'none';
    document.body.style.overflow = '';
  }, { once: true });
}

// Close on backdrop click
document.querySelectorAll('.modal-overlay').forEach(modal => {
  modal.addEventListener('click', e => {
    if (e.target === modal) closeModal(modal.id);
  });
});

// Close on Escape key
document.addEventListener('keydown', e => {
  if (e.key === 'Escape') {
    const openModalEl = document.querySelector('.modal-overlay.open');
    if (openModalEl) closeModal(openModalEl.id);
  }
});

// Wire up all close buttons (.modal-close header button and .modal-close-btn footer button)
document.querySelectorAll('.modal-close, .modal-close-btn').forEach(btn => {
  btn.addEventListener('click', () => {
    const modal = btn.closest('.modal-overlay');
    if (modal) closeModal(modal.id);
  });
});
