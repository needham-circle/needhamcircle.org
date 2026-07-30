---
title: "Needham Circle — Contact"
description: "Get in touch with the Needham Circle organizers."
permalink: /contact
---

<h2>Contact</h2>

<div class="thanks" role="status" hidden data-thanks>Thanks for reaching out! Your message has been sent to the organizers, and we'll be in touch.</div>

<div data-form-region>
  <p>Have a question, an idea, or want to get involved? Send the organizers a note and we'll get back to you.</p>

  <div class="error-summary" role="alert" hidden data-error-summary>There was a problem sending your message. Please check the fields and try again.</div>

  <form data-remote data-endpoint="{{ site.contact_endpoint }}">
    <div class="field">
      <label for="name">Name <span class="required-marker" aria-hidden="true">*</span></label>
      <input id="name" type="text" name="name" required maxlength="100">
    </div>

    <div class="field">
      <label for="email">Email <span class="required-marker" aria-hidden="true">*</span></label>
      <input id="email" type="email" name="email" required maxlength="200">
      <small class="field-hint">So we can reply to you. It is not shown publicly.</small>
    </div>

    <div class="field">
      <label for="subject">Subject</label>
      <input id="subject" type="text" name="subject" maxlength="200">
    </div>

    <div class="field">
      <label for="message">Message <span class="required-marker" aria-hidden="true">*</span></label>
      <textarea id="message" name="message" rows="6" required maxlength="5000"></textarea>
    </div>

    <div class="visually-hidden" aria-hidden="true">
      <label for="website">Leave this field empty</label>
      <input id="website" type="text" name="website" tabindex="-1" autocomplete="off">
    </div>

    <p><button type="submit">Send message</button></p>
  </form>

  <noscript>
    <p class="empty-state">Sending a message needs JavaScript. Please enable it and reload the page.</p>
  </noscript>
</div>

<script src="{{ '/js/forms.js' | relative_url }}" defer></script>
