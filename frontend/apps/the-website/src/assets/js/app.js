/* ---------- Shared helpers ---------- */
function validateEmail(email) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
}
  
function endpointFor(kind) {
  // interest-service is exposed via the gateway
  return kind === 'worker'
    ? '/api/v1/interest/worker'
    : '/api/v1/interest/pm';
}

function successElement(text) {
  const p = document.createElement('p');
  Object.assign(p.style, {
    fontSize: '1.25rem',
    fontWeight: '600',
    color: 'var(--c-accent)',
    marginTop: '1.5rem',
  });
  p.textContent = text;
  return p;
}

/* ---------- Core wire-up for ANY .signup-form ---------- */
function wireUpSignupForm(form) {
  if (!form || form.dataset.formInitialized === 'true') return;
  form.dataset.formInitialized = 'true';

  form.addEventListener('submit', async (evt) => {
    evt.preventDefault();

    const kind   = form.dataset.kind;          // "pm" | "worker"
    const input  = form.querySelector('input[type="email"]');
    const button = form.querySelector('button');
    const respEl = form.querySelector('.response-message');
    if (!input || !button || !respEl) return;

    /* clear any prior state */
    respEl.classList.add('hidden');
    respEl.textContent = '';
    respEl.style.color = '';

    const email = input.value.trim();
    if (!validateEmail(email)) {
      respEl.textContent = 'Please enter a valid e-mail address.';
      respEl.style.color = 'red';
      respEl.classList.remove('hidden');
      return;
    }

    const originalText = button.textContent;
    button.disabled = true;
    button.textContent = 'SENDING…';

    try {
      const res = await fetch(endpointFor(kind), {
        method : 'POST',
        headers: { 'Content-Type': 'application/json' },
        body   : JSON.stringify({ email })
      });

      const body = await res.json().catch(() => ({}));

      if (res.ok) {
        /* Dynamic panel gets its own success box */
        if (form.id === 'dynamic-signup-form') {
          const successBox = document.getElementById('dynamic-signup-success');
          form.classList.add('hidden');
          successBox.innerHTML = '';
          successBox.appendChild(
            successElement(body.message || 'Received – check your inbox!')
          );
          successBox.classList.remove('hidden');
        } else {
          /* Replace static form outright */
          form.replaceWith(
            successElement(body.message || 'Received – check your inbox!')
          );
        }
      } else {
        respEl.textContent =
          body.message || 'Something went wrong. Please try again.';
        respEl.style.color = 'red';
        respEl.classList.remove('hidden');
      }
    } catch (err) {
      respEl.textContent = 'Network error. Please try again later.';
      respEl.style.color = 'red';
      respEl.classList.remove('hidden');
    } finally {
      if (button.isConnected) {
        button.disabled = false;
        button.textContent =
          form.id === 'dynamic-signup-form' ? 'Reserve Your Spot' : 'Reserve Your Spot';
      }
    }
  });
}

/* ---------- Dynamic PM / Worker panel ---------- */
function initDynamicSignupControls () {
  const startButtons   = document.querySelectorAll('.startButton[data-signup-type]');
  const signupSection  = document.getElementById('dynamic-signup-section');
  const signupTitle    = document.getElementById('dynamic-signup-title');
  const signupForm     = document.getElementById('dynamic-signup-form');
  const signupSuccess  = document.getElementById('dynamic-signup-success');

  if (!startButtons.length || !signupSection || !signupTitle || !signupForm || !signupSuccess) {
    console.warn('Dynamic signup elements missing.');
    return;
  }

  /* make sure the dynamic form is wired exactly once */
  wireUpSignupForm(signupForm);

  startButtons.forEach(btn => {
    btn.addEventListener('click', () => {
      const type = btn.dataset.signupType;

      // reset UI
      signupForm.classList.remove('hidden');
      signupSuccess.classList.add('hidden');
      signupSuccess.innerHTML = '';
      signupForm.reset();
      signupForm.querySelector('.response-message')?.classList.add('hidden');
      const submitBtn = signupForm.querySelector('button');
      if (submitBtn) { submitBtn.disabled = false; submitBtn.textContent = 'Reserve Your Spot'; }

      // configure
      signupTitle.textContent =
        type === 'pm' ? 'Property Manager Early Access' : 'Worker Early Access';
      signupForm.dataset.kind = type;

      signupSection.classList.remove('hidden');
      signupForm.querySelector('input[type="email"]')?.focus();
      signupSection.scrollIntoView({ behavior: 'smooth', block: 'center' });
    });
  });
}

/* ---------- Static forms elsewhere on the page ---------- */
function initSignupForms() {
  document.querySelectorAll('.signup-form').forEach(wireUpSignupForm);
}

/* ---------- Scroll-in animation ---------- */
function initScrollAnimations () {
  const els = document.querySelectorAll('.js-scroll-animate-init');
  if (!els.length) return;

  const obs = new IntersectionObserver((entries, o) => {
    entries.forEach(entry => {
      if (entry.isIntersecting) {
        entry.target.style.opacity = '1';
        entry.target.style.transform = 'translateY(0)';
        o.unobserve(entry.target);
      }
    });
  }, { threshold: 0.1 });

  els.forEach(el => obs.observe(el));
}

/* ---------- Bootstrap ---------- */
document.addEventListener('DOMContentLoaded', () => {
  initDynamicSignupControls();  // PM / Worker panel
  initSignupForms();            // any .signup-form already in DOM
  initScrollAnimations();       // fade-in on scroll
  initDeleteAccountForm();  // account deletion form
  initDeleteAccountAuthForms(); // account deletion auth forms

  const yr = document.getElementById('currentYear');
  if (yr) yr.textContent = new Date().getFullYear();

  document.getElementById('home')?.classList.remove('hidden');
  window.scrollTo(0, 0);
});



/* ---------- Account Deletion Forms ---------- */
function initDeleteAccountForm() {
  const form = document.getElementById('delete-account-form');
  if (!form) return;
  wireUpDeletionRequest(form);
}

function initDeleteAccountAuthForms() {
  const token = new URLSearchParams(window.location.search).get('token') || sessionStorage.getItem('pending_token');
  const totpForm = document.getElementById('totp-form');
  const codesForm = document.getElementById('codes-form');
  if (!token || (!totpForm && !codesForm)) return;

  if (totpForm) {
    totpForm.addEventListener('submit', evt => {
      evt.preventDefault();
      const code = totpForm.querySelector('input[name="totp"]').value.trim();
      submitDeletionAuth({ pending_token: token, totp_code: code }, totpForm);
    });
  }

  if (codesForm) {
    codesForm.addEventListener('submit', evt => {
      evt.preventDefault();
      const email = codesForm.querySelector('input[name="email_code"]').value.trim();
      const sms = codesForm.querySelector('input[name="sms_code"]').value.trim();
      submitDeletionAuth({ pending_token: token, email_code: email, sms_code: sms }, codesForm);
    });
  }
}

function wireUpDeletionRequest(form) {
  if (form.dataset.formInitialized === 'true') return;
  form.dataset.formInitialized = 'true';
  form.addEventListener('submit', async evt => {
    evt.preventDefault();
    const input = form.querySelector('input[type="email"]');
    const button = form.querySelector('button');
    const respEl = form.querySelector('.response-message');
    const email = input.value.trim();
    if (!validateEmail(email)) {
      respEl.textContent = 'Please enter a valid e-mail address.';
      respEl.style.color = 'red';
      respEl.classList.remove('hidden');
      return;
    }
    respEl.classList.add('hidden');
    button.disabled = true;
    try {
      const res = await fetch('/auth/v1/worker/initiate-deletion', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email })
      });
      const body = await res.json().catch(() => ({}));
      if (res.ok) {
        sessionStorage.setItem('pending_token', body.pending_token);
        window.location.href = '/delete-account-auth.html?token=' + encodeURIComponent(body.pending_token);
      } else {
        respEl.textContent = body.message || 'Something went wrong. Please try again.';
        respEl.style.color = 'red';
        respEl.classList.remove('hidden');
      }
    } catch (err) {
      respEl.textContent = 'Network error. Please try again later.';
      respEl.style.color = 'red';
      respEl.classList.remove('hidden');
    } finally {
      button.disabled = false;
    }
  });
}

async function submitDeletionAuth(payload, form) {
  const button = form.querySelector('button');
  const respEl = form.querySelector('.response-message');
  respEl.classList.add('hidden');
  button.disabled = true;
  try {
    const res = await fetch('/auth/v1/worker/confirm-deletion', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload)
    });
    const body = await res.json().catch(() => ({}));
    if (res.ok) {
      form.parentElement.innerHTML = `<p>${body.message || 'Request submitted.'}</p>`;
      sessionStorage.removeItem('pending_token');
    } else {
      respEl.textContent = body.message || 'Invalid codes. Please try again.';
      respEl.style.color = 'red';
      respEl.classList.remove('hidden');
    }
  } catch (err) {
    respEl.textContent = 'Network error. Please try again later.';
    respEl.style.color = 'red';
    respEl.classList.remove('hidden');
  } finally {
    button.disabled = false;
  }
}