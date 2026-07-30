---
title: "Needham Circle — Submit an Event"
description: "Submit a community event to the Needham Circle calendar."
permalink: /submit
---

<h2>Submit</h2>

<div class="thanks" role="status" hidden data-thanks>Thanks! Your submission has been received and is awaiting approval.</div>

<div data-form-region>
  <div class="error-summary" role="alert" hidden data-error-summary>There was a problem with your submission. Please check the fields and try again.</div>

  <form data-remote data-endpoint="{{ site.submit_endpoint }}">
    <div class="field">
      <label for="title">Event Title <span class="required-marker" aria-hidden="true">*</span></label>
      <input id="title" type="text" name="title" required maxlength="200">
    </div>

    <div class="field">
      <label for="host">Name of host organization/business <span class="required-marker" aria-hidden="true">*</span></label>
      <input id="host" type="text" name="host" required maxlength="200">
    </div>

    <div class="field">
      <label for="email">Email <span class="required-marker" aria-hidden="true">*</span></label>
      <input id="email" type="email" name="email" required maxlength="200">
      <small class="field-hint">An email address so our moderators can reach you about your event. It is not shown publicly.</small>
    </div>

    <div class="field">
      <label for="start_time">Start <span class="required-marker" aria-hidden="true">*</span></label>
      <input id="start_time" type="datetime-local" name="start_time" required>
    </div>

    <div class="field">
      <label for="end_time">End <span class="required-marker" aria-hidden="true">*</span></label>
      <input id="end_time" type="datetime-local" name="end_time" required>
    </div>

    <div class="field">
      <label for="location">Location</label>
      <input id="location" type="text" name="location" maxlength="200">
    </div>

    <div class="field">
      <label for="url">URL</label>
      <input
        id="url"
        type="url"
        name="url"
        maxlength="500"
        pattern="https://.*"
      >
      <small class="field-hint">The link to the event's page. It must start with https://.</small>
    </div>

    <div class="field">
      <label for="description">Description</label>
      <textarea id="description" name="description" rows="4" maxlength="2000"></textarea>
    </div>

    <div class="visually-hidden" aria-hidden="true">
      <label for="website">Leave this field empty</label>
      <input id="website" type="text" name="website" tabindex="-1" autocomplete="off">
    </div>

    <p><button type="submit">Submit</button></p>
  </form>

  <small class="submit-disclaimer">
    <p>Thank you for contributing to Needham Circle's Community Calendar! To keep
    this a welcoming, accessible resource for everyone, please ensure your
    submission meets the following criteria before posting.</p>
    <ul>
      <li><strong>Free and open:</strong> All events must be free to attend and open to the general public.</li>
      <li><strong>Non-political:</strong> We do not accept partisan, political campaign, or candidate fundraising events.</li>
      <li><strong>Community-focused:</strong> Listings should provide clear value to the local public (e.g., workshops, cultural events, family activities).</li>
      <li><strong>Review:</strong> All submissions are moderated for alignment with our guidelines and may be edited for length/clarity.</li>
      <li><strong>Updates:</strong> Organizers are responsible for accuracy. Please notify us immediately if your event is canceled or rescheduled.</li>
    </ul>
    <p>Listing an event is for informational purposes only and does not
    constitute an endorsement of the event, organizers, or content.</p>
  </small>

  <noscript>
    <p class="empty-state">Submitting an event needs JavaScript. Please enable it and reload the page.</p>
  </noscript>
</div>

<script src="{{ '/js/forms.js' | relative_url }}" defer></script>
