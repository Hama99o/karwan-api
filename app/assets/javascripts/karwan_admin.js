// ── ONE PRESS, ONE REQUEST — AND THE CONFIRM THAT WAS NEVER ASKED ──────────
//
// Every intervention form in this console is `data: { turbo: false }`, so the
// browser submits it natively and Turbo's own submit-button disabling never
// runs. Rails' `data-disable-with` and `data-confirm` are read only by
// rails-ujs, and Administrate 1.0 does not ship it. Found 24 Sept 2026:
//
//   * a double click on "Top up" sent two POSTs and credited a courier twice;
//   * nine `data-confirm` prompts — "Mark KQA… failed? This is a money
//     decision." among them — had never once been shown to anybody.
//
// So this does both, for the native forms only. Turbo's forms already disable
// their submitter and take `data-turbo-confirm`; guarding them here too would
// leave a form dead after a failed Turbo fetch, which re-enables nothing.
//
// RE-ENABLED WHEN THE PAGE COMES BACK. A rejected form redirects to a fresh
// page, so it is usable again anyway. A failed request (no signal, a browser
// error page) is left with Back, and Back restores this page from the
// back-forward cache with its buttons still disabled — `pageshow` undoes that,
// so a form that did not go through is never left unusable.
(function () {
  var NATIVE = 'form[data-turbo="false"]';
  var DISABLED_HERE = "data-karwan-disabled";

  document.addEventListener("submit", function (event) {
    var form = event.target;
    if (!(form instanceof HTMLFormElement) || !form.matches(NATIVE)) return;

    if (form.hasAttribute("data-karwan-submitting")) {
      event.preventDefault();
      return;
    }

    var submitter = event.submitter;
    var message = (submitter && submitter.getAttribute("data-confirm")) || form.getAttribute("data-confirm");
    if (message && !window.confirm(message)) {
      event.preventDefault();
      return;
    }

    form.setAttribute("data-karwan-submitting", "");
    // After this turn, so the browser has already taken the pressed button's
    // name and value into the request — a disabled button is left out of it.
    setTimeout(function () {
      form.querySelectorAll('button, input[type="submit"]').forEach(function (button) {
        if (button.disabled) return;
        button.disabled = true;
        button.setAttribute(DISABLED_HERE, "");
      });
    }, 0);
  }, true);

  window.addEventListener("pageshow", function () {
    document.querySelectorAll("form[data-karwan-submitting]").forEach(function (form) {
      form.removeAttribute("data-karwan-submitting");
    });
    document.querySelectorAll("[" + DISABLED_HERE + "]").forEach(function (button) {
      button.disabled = false;
      button.removeAttribute(DISABLED_HERE);
    });
  });
})();
