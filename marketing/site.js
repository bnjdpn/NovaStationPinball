(function () {
  'use strict';

  document.querySelectorAll('[data-language-picker]').forEach(function (picker) {
    picker.addEventListener('change', function () {
      if (picker.value) { window.location.assign(picker.value); }
    });
  });

  document.querySelectorAll('.support-form').forEach(function (form) {
    form.addEventListener('submit', function (event) {
      if (!window.fetch || !window.FormData) { return; }
      event.preventDefault();
      var button = form.querySelector('button[type="submit"]');
      var status = form.querySelector('.form-status');
      if (button) { button.disabled = true; }
      if (status) { status.textContent = form.dataset.sending; }
      window.fetch(form.action, {
        method: 'POST',
        body: new window.FormData(form),
        headers: { Accept: 'application/json' }
      }).then(function (response) {
        if (!response.ok) { throw new Error('support request failed'); }
        form.reset();
        if (status) { status.textContent = form.dataset.success; }
      }).catch(function () {
        if (status) { status.textContent = form.dataset.error; }
      }).finally(function () {
        if (button) { button.disabled = false; }
      });
    });
  });
}());
