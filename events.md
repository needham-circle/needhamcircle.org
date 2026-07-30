---
title: "Needham Circle — Events"
description: "Upcoming community events in Needham Circle. Browse what's happening, and submit your own events."
permalink: /events
---

<h2 class="visually-hidden">Upcoming Events</h2>

<div class="event-filters" data-filters>
  <div class="filter-bar">
    <form class="filter-search-form">
      <input
        class="filter-search"
        type="search"
        name="q"
        placeholder="Search events"
        aria-label="Search events"
        data-search
      >
    </form>

    <details class="source-filter" data-source-filter>
      <summary class="source-filter-trigger">
        Organizations<span class="source-filter-count" data-source-count hidden>0</span>
        <span class="source-filter-caret" aria-hidden="true"></span>
      </summary>
      <div class="source-filter-menu">
        <ul class="source-filter-list">
          {% for source in site.data.sources %}
            <li>
              <a
                class="source-option"
                href="?source={{ source.slug }}"
                data-source="{{ source.slug }}"
                data-label="{{ source.label }}"
                role="checkbox"
                aria-checked="false"
              ><span class="source-swatch" style="--event-color: {{ source.color }}" aria-hidden="true"></span>{{ source.label }}</a>
            </li>
          {% endfor %}
        </ul>
        <div class="source-filter-actions">
          <a href="?" data-select-all>Select all</a>
          <a href="?" data-clear-sources>Clear</a>
        </div>
      </div>
    </details>

    <div class="view-toggle" data-view-toggle role="group" aria-label="Events view">
      <a class="view-option" href="?" data-view="list" aria-current="true">List</a>
      <a class="view-option" href="?view=calendar" data-view="calendar" aria-current="false">Calendar</a>
    </div>
  </div>

  <div class="applied-filters" data-applied hidden></div>
</div>

<div data-events data-endpoint="{{ site.events_endpoint }}">
  <noscript>
    <p class="empty-state">The events list needs JavaScript to load. Please enable it and reload the page.</p>
  </noscript>
</div>

<script type="application/json" data-sources-data>{{ site.data.sources | jsonify }}</script>

<template data-error>
  <p class="empty-state">We're having trouble loading events right now. Please check back soon.</p>
</template>

<template data-skeleton="list">
  <div class="events-skeleton" aria-hidden="true">
    <div class="skeleton-month"></div>
    {% for i in (1..4) %}
      <div class="skeleton-event">
        <span class="skeleton-line skeleton-time"></span>
        <span class="skeleton-line skeleton-title"></span>
        <span class="skeleton-line skeleton-loc"></span>
      </div>
    {% endfor %}
  </div>
</template>

<template data-skeleton="calendar">
  <div class="cal-scroll" aria-hidden="true">
    <table class="cal-month">
      <caption class="cal-month-title"><span class="skeleton-line skeleton-cal-title"></span></caption>
      <thead>
        <tr>
          {% for i in (1..7) %}
            <th scope="col"><span class="skeleton-line skeleton-cal-head"></span></th>
          {% endfor %}
        </tr>
      </thead>
      <tbody>
        {% for i in (1..5) %}
          <tr>
            {% for j in (1..7) %}
              <td class="cal-day"><span class="skeleton-line skeleton-cal-num"></span></td>
            {% endfor %}
          </tr>
        {% endfor %}
      </tbody>
    </table>
  </div>
</template>

<script src="{{ '/js/events.js' | relative_url }}" defer></script>
