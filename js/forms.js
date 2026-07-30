// Submits the event and contact forms to their Cloud Run functions as JSON
// and renders the outcome in place: the thanks banner on success, per-field
// errors on validation failure, and the error summary otherwise.
(function () {
  "use strict";

  document.querySelectorAll("form[data-remote]").forEach(function (form) {
    var endpoint = form.dataset.endpoint;
    var region = form.closest("[data-form-region]");
    var thanks = document.querySelector("[data-thanks]");
    var summary = region ? region.querySelector("[data-error-summary]") : null;
    var summaryText = summary ? summary.textContent : "";
    var button = form.querySelector("button[type=submit]");

    function clearErrors() {
      form.querySelectorAll(".field-error").forEach(function (node) { node.remove(); });
      if (summary) {
        summary.hidden = true;
        summary.textContent = summaryText;
      }
    }

    function showSummary(text) {
      if (!summary) return;
      if (text) summary.textContent = text;
      summary.hidden = false;
      summary.scrollIntoView({ block: "nearest" });
    }

    function showFieldErrors(errors) {
      Object.keys(errors).forEach(function (name) {
        var input = form.querySelector('[name="' + name + '"]');
        var field = input && input.closest(".field");
        if (!field) return;
        errors[name].forEach(function (message) {
          var error = document.createElement("span");
          error.className = "field-error";
          error.textContent = message;
          field.appendChild(error);
        });
      });
      showSummary();
    }

    form.addEventListener("submit", function (event) {
      event.preventDefault();
      clearErrors();
      if (button) button.disabled = true;

      var payload = {};
      new FormData(form).forEach(function (value, key) { payload[key] = String(value); });

      fetch(endpoint, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload)
      })
        .then(function (response) {
          return response.json().catch(function () { return {}; }).then(function (body) {
            if (response.ok) {
              if (region) region.hidden = true;
              if (thanks) thanks.hidden = false;
              window.scrollTo({ top: 0 });
            } else if (response.status === 422 && body.errors) {
              showFieldErrors(body.errors);
            } else {
              showSummary(body.error);
            }
          });
        })
        .catch(function () {
          showSummary();
        })
        .then(function () {
          if (button) button.disabled = false;
        });
    });
  });
})();
