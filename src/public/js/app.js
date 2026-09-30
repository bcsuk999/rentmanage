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

  // Button spinner while a request is loading: disable the submit button and
  // show a spinner so double taps cannot fire the request twice. The next
  // page load renders a fresh button, so no reset is needed.
  document.querySelectorAll('form').forEach((form) => {
    form.addEventListener('submit', (event) => {
      // Skip when another handler cancelled the submit (e.g. confirm dialog).
      if (event.defaultPrevented) return;
      const button = form.querySelector('button[type="submit"]');
      if (!button || button.disabled) return;
      button.disabled = true;
      button.classList.add('btn-loading');
      const spinner = document.createElement('span');
      spinner.className = 'btn-spinner';
      spinner.setAttribute('aria-hidden', 'true');
      button.prepend(spinner);
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
  const openBtn = document.querySelector('[data-sidebar-open]');
  const sidebar = document.getElementById('app-sidebar');
  const backdrop = document.querySelector('.sidebar-backdrop');
  if (!openBtn || !sidebar || !backdrop) return;

  function open() {
    sidebar.classList.add('open');
    sidebar.setAttribute('aria-hidden', 'false');
    backdrop.hidden = false;
    openBtn.setAttribute('aria-expanded', 'true');
    document.body.classList.add('sidebar-open');
    sidebar.querySelector('.sidebar-close')?.focus();
  }

  function close(returnFocus = true) {
    if (!sidebar.classList.contains('open')) return;
    sidebar.classList.remove('open');
    sidebar.setAttribute('aria-hidden', 'true');
    backdrop.hidden = true;
    openBtn.setAttribute('aria-expanded', 'false');
    document.body.classList.remove('sidebar-open');
    if (returnFocus) openBtn.focus();
  }

  openBtn.addEventListener('click', open);
  sidebar.querySelectorAll('[data-sidebar-close]').forEach((el) => {
    el.addEventListener('click', () => close());
  });
  backdrop.addEventListener('click', () => close());
  // Choosing a destination navigates away; close without stealing focus.
  sidebar.querySelectorAll('.sidebar-nav a').forEach((link) => {
    link.addEventListener('click', () => close(false));
  });
  document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape') close();
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
