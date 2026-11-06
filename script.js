const menuToggle = document.querySelector('.menu-toggle');
const navLinks = document.querySelector('.nav-links');

if (menuToggle && navLinks) {
  menuToggle.addEventListener('click', () => {
    const isOpen = navLinks.classList.toggle('open');
    menuToggle.setAttribute('aria-expanded', String(isOpen));
    menuToggle.setAttribute('aria-label', isOpen ? 'Close navigation menu' : 'Open navigation menu');
  });

  navLinks.querySelectorAll('a').forEach(link => {
    link.addEventListener('click', () => {
      navLinks.classList.remove('open');
      menuToggle.setAttribute('aria-expanded', 'false');
    });
  });
}

document.querySelectorAll('[data-demo]').forEach(link => {
  link.addEventListener('click', event => {
    event.preventDefault();
    const toast = document.querySelector('.toast');
    const action = link.dataset.demo;
    toast.textContent = `${action} will be available when student accounts and enrollment are connected.`;
    toast.classList.add('show');
    window.clearTimeout(window.__admirankToastTimer);
    window.__admirankToastTimer = window.setTimeout(() => toast.classList.remove('show'), 3200);
  });
});

document.getElementById('year').textContent = new Date().getFullYear();
