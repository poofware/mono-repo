import poofLogo from '/assets/images/POOF_LOGO-LC_BW.svg'; // Add this line
import { initBackgroundScene } from './trash-bag.js';

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
    // console.warn('Dynamic signup elements missing.'); // Comment out to reduce console noise
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
  try {
    initBackgroundScene();          // 3D Background
  } catch (e) {
    console.error('Failed to init 3D background:', e);
  }
  
  try {
    initDynamicSignupControls();  // PM / Worker panel
    initSignupForms();            // any .signup-form already in DOM
    initScrollAnimations();       // fade-in on scroll
    initDeleteAccountForm();  // account deletion form
    initDeleteAccountAuthForms(); // account deletion auth forms
  } catch (e) {
    console.error('Failed to init app logic:', e);
  }

  const yr = document.getElementById('currentYear');
  if (yr) yr.textContent = new Date().getFullYear();

  document.getElementById('home')?.classList.remove('hidden');
  window.scrollTo(0, 0);
});



/* ---------- Account Deletion Forms ---------- */
function initDeleteAccountForm() {
  const form = document.getElementById('delete-account-form');
  if (!form) return;

  const workerBtn = document.getElementById('account-type-worker');
  const pmBtn = document.getElementById('account-type-pm');
  const hiddenInput = document.getElementById('account-type');

  if (!workerBtn || !pmBtn || !hiddenInput) return;

  workerBtn.addEventListener('click', () => {
    hiddenInput.value = 'worker';
    workerBtn.classList.add('selected');
    pmBtn.classList.remove('selected');
  });

  pmBtn.addEventListener('click', () => {
    hiddenInput.value = 'pm';
    pmBtn.classList.add('selected');
    workerBtn.classList.remove('selected');
  });
  
  wireUpDeletionRequest(form);
}


function initDeleteAccountAuthForms() {
  const params = new URLSearchParams(window.location.search);
  const token = params.get('token') || sessionStorage.getItem('pending_token');
  const accountType = params.get('type') || sessionStorage.getItem('account_type');

  const totpForm = document.getElementById('totp-form');
  const codesForm = document.getElementById('codes-form');
  if (!token || !accountType || (!totpForm && !codesForm)) return;

  if (totpForm) {
    totpForm.addEventListener('submit', evt => {
      evt.preventDefault();
      const code = totpForm.querySelector('input[name="totp"]').value.trim();
      submitDeletionAuth({ pending_token: token, totp_code: code }, totpForm, accountType);
    });
  }

  if (codesForm) {
    codesForm.addEventListener('submit', evt => {
      evt.preventDefault();
      const email = codesForm.querySelector('input[name="email_code"]').value.trim();
      const sms = codesForm.querySelector('input[name="sms_code"]').value.trim();
      submitDeletionAuth({ pending_token: token, email_code: email, sms_code: sms }, codesForm, accountType);
    });
  }
}

/**
 * MODIFIED: This function now handles UI loading states (text and spinner)
 * inside the submit button for a more modern feel.
 */
function wireUpDeletionRequest(form) {
  if (form.dataset.formInitialized === 'true') return;
  form.dataset.formInitialized = 'true';
  form.addEventListener('submit', async evt => {
    evt.preventDefault();
    const input = form.querySelector('input[type="email"]');
    const button = form.querySelector('button[type="submit"]'); // Correctly select the submit button
    const respEl = form.querySelector('.response-message');
    const accountTypeInput = form.querySelector('#account-type'); // Select within the form context
    
    // Get button text and spinner elements for loading state
    const buttonText = button.querySelector('.button-text');
    const buttonSpinner = button.querySelector('.spinner');

    const email = input.value.trim();
    if (!validateEmail(email)) {
      respEl.textContent = 'Please enter a valid e-mail address.';
      respEl.classList.remove('hidden');
      return;
    }
    
    respEl.classList.add('hidden');
    button.disabled = true;
    const originalText = buttonText.textContent;
    if(buttonText) buttonText.textContent = 'Sending...';
    if(buttonSpinner) buttonSpinner.classList.remove('hidden');

    const accountType = accountTypeInput.value;
    const endpoint = `/auth/v1/${accountType}/initiate-deletion`;

    try {
      const res = await fetch(endpoint, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email })
      });
      const body = await res.json().catch(() => ({}));
      if (res.ok) {
        sessionStorage.setItem('pending_token', body.pending_token);
        sessionStorage.setItem('account_type', accountType);
        window.location.href = `/delete-account-auth.html?token=${encodeURIComponent(body.pending_token)}&type=${accountType}`;
      } else {
        respEl.textContent = body.message || 'Something went wrong. Please try again.';
        respEl.classList.remove('hidden');
      }
    } catch (err) {
      respEl.textContent = 'Network error. Please try again later.';
      respEl.classList.remove('hidden');
    } finally {
      if (button.isConnected) {
        button.disabled = false;
        if(buttonText) buttonText.textContent = originalText;
        if(buttonSpinner) buttonSpinner.classList.add('hidden');
      }
    }
  });
}

/**
 * MODIFIED: This function now handles UI loading states and replaces the
 * entire form card with a success message for a better UX.
 */
async function submitDeletionAuth(payload, form, accountType) {
  const button = form.querySelector('button');
  const respEl = form.querySelector('.response-message');
  
  // Get button text and spinner elements for loading state
  const buttonText = button.querySelector('.button-text');
  const buttonSpinner = button.querySelector('.spinner');

  respEl.classList.add('hidden');
  button.disabled = true;
  const originalText = buttonText.textContent;
  if(buttonText) buttonText.textContent = 'Confirming...';
  if(buttonSpinner) buttonSpinner.classList.remove('hidden');

  const endpoint = `/auth/v1/${accountType}/confirm-deletion`;

  try {
    const res = await fetch(endpoint, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload)
    });
    const body = await res.json().catch(() => ({}));
    if (res.ok) {
      // On success, replace the entire card's content with a success message.
      const authCard = document.getElementById('auth-card');
      if (authCard) {
        authCard.innerHTML = `
          <img src="${poofLogo}" alt="Poof logo" class="w-24 mx-auto" onerror="this.onerror=null; this.src='https://placehold.co/96x48/000000/FFFFFF?text=Poof';">
          <div class="text-center space-y-4 py-8">
            <svg class="mx-auto h-16 w-16 text-green-500" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
              <path stroke-linecap="round" stroke-linejoin="round" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
            </svg>
            <h1 class="text-2xl font-bold text-slate-900">Request Submitted</h1>
            <p class="text-slate-500">Your account deletion request has been successfully submitted. You will receive an email notification when the deletion is complete. This may take up to 30 days.</p>
            <a href="/" class="inline-block mt-4 text-[#743ee4] hover:underline font-semibold">Return to Homepage</a>
          </div>
        `;
      }
      sessionStorage.removeItem('pending_token');
      sessionStorage.removeItem('account_type');
    } else {
      respEl.textContent = body.message || 'Invalid codes. Please try again.';
      respEl.classList.remove('hidden');
    }
  } catch (err) {
    respEl.textContent = 'Network error. Please try again later.';
    respEl.classList.remove('hidden');
  } finally {
    // Check if button is still in the DOM before trying to update it
    if (button.isConnected) {
        button.disabled = false;
        if(buttonText) buttonText.textContent = originalText;
        if(buttonSpinner) buttonSpinner.classList.add('hidden');
    }
  }
}