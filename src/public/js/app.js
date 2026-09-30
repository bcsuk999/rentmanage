document.addEventListener('DOMContentLoaded', () => {
  // Room period picker: value is "from|to" and reloads the room with that range.
  document.querySelectorAll('[data-range-select]').forEach((select) => {
    select.addEventListener('change', () => {
      const [from, to] = select.value.split('|');
      if (!from || !to) return;
      const url = new URL(window.location.href);
      url.searchParams.set('from', from);
      url.searchParams.set('to', to);
      window.location.href = url.toString();
    });
  });

  // Confirm destructive / state changing submits.
  document.querySelectorAll('form[data-confirm]').forEach((form) => {
    form.addEventListener('submit', (event) => {
      if (!window.confirm(form.dataset.confirm)) event.preventDefault();
    });
  });

  document.querySelectorAll('[data-reload]').forEach((button) => {
    button.addEventListener('click', () => window.location.reload());
  });

  // Popup toast cards: manual close + auto-dismiss.
  document.querySelectorAll('[data-toast]').forEach((el) => {
    const dismiss = () => {
      el.classList.add('hide');
      window.setTimeout(() => el.remove(), 350);
    };
    el.querySelector('[data-toast-close]')?.addEventListener('click', dismiss);
    window.setTimeout(dismiss, 8000);
  });

  // Pre-select the pending amount when adding a payment.
  document.querySelectorAll('input[name="amount"]').forEach((input) => {
    input.addEventListener('focus', () => input.select());
  });

  setupMobileNav();
  setupInstallPrompt();
  registerServiceWorker();
});

function setupMobileNav() {
  const toggle = document.querySelector('[data-nav-toggle]');
  const nav = document.getElementById('main-nav');
  if (!toggle || !nav) return;
  toggle.addEventListener('click', () => {
    const open = nav.classList.toggle('open');
    toggle.setAttribute('aria-expanded', String(open));
  });
}

function setupInstallPrompt() {
  const button = document.querySelector('[data-install]');
  if (!button) return;
  let deferredPrompt = null;
  window.addEventListener('beforeinstallprompt', (event) => {
    event.preventDefault();
    deferredPrompt = event;
    button.hidden = false;
  });
  button.addEventListener('click', async () => {
    if (!deferredPrompt) return;
    deferredPrompt.prompt();
    await deferredPrompt.userChoice;
    deferredPrompt = null;
    button.hidden = true;
  });
  window.addEventListener('appinstalled', () => {
    button.hidden = true;
  });
}

function registerServiceWorker() {
  if (!('serviceWorker' in navigator)) return;
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('/sw.js', { scope: '/' }).catch(() => {
      /* offline support is optional */
    });
  });
}
