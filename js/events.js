// Renders the events page from the ListEvents function: fetches the JSON,
// renders the list and month-grid calendar views, and drives the filter bar.
// Source filtering and the view toggle are purely client-side over the
// fetched set; the search box re-queries the function, whose `q` is handled
// by the Calendar API.
(function () {
  "use strict";

  var filters = document.querySelector("[data-filters]");
  var results = document.querySelector("[data-events]");
  if (!filters || !results) return;

  var endpoint = results.dataset.endpoint;
  var sources = JSON.parse(document.querySelector("[data-sources-data]").textContent);

  // ---------------------------------------------------------------------
  // Dates. Events arrive with Google's own start/end payloads: timed events
  // as RFC3339 dateTime strings whose offset is already Needham-local, and
  // all-day events as bare dates. All date math parses the wall-clock
  // components straight out of the string, so times render in the event's
  // own offset rather than the viewer's zone, and represents whole days as
  // UTC-midnight timestamps so arithmetic never crosses DST.

  var DAY = 86400000;
  var MAX_RESULTS = 250; // one page from ListEvents; must match the function's cap
  var MAX_LINES = 4; // rows per calendar day cell before "+N more"
  var WALL = /^(\d{4})-(\d{2})-(\d{2})(?:T(\d{2}):(\d{2}))?/;
  var WEEKDAYS = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];
  var MONTHS = [
    "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December"
  ];

  function wall(value) {
    var match = WALL.exec(value);
    return { y: +match[1], mo: +match[2], d: +match[3], h: match[4] ? +match[4] : 0, min: match[5] ? +match[5] : 0 };
  }

  function dayValue(w) {
    return Date.UTC(w.y, w.mo - 1, w.d);
  }

  function dayParts(day) {
    var date = new Date(day);
    return { y: date.getUTCFullYear(), mo: date.getUTCMonth() + 1, d: date.getUTCDate(), wd: date.getUTCDay() };
  }

  function monthOf(day) {
    var p = dayParts(day);
    return Date.UTC(p.y, p.mo - 1, 1);
  }

  function shiftMonth(month, by) {
    var p = dayParts(month);
    return Date.UTC(p.y, p.mo - 1 + by, 1);
  }

  // Today in Needham's zone, independent of the visitor's clock zone.
  function todayValue() {
    return dayValue(wall(new Intl.DateTimeFormat("en-CA", { timeZone: "America/New_York" }).format(new Date())));
  }

  function hour12(h) {
    return h % 12 === 0 ? 12 : h % 12;
  }

  function pad(n) {
    return (n < 10 ? "0" : "") + n;
  }

  function longDate(day) {
    var p = dayParts(day);
    return WEEKDAYS[p.wd] + ", " + MONTHS[p.mo - 1] + " " + p.d;
  }

  function clockTime(w) {
    return hour12(w.h) + ":" + pad(w.min) + " " + (w.h < 12 ? "AM" : "PM");
  }

  // ---------------------------------------------------------------------
  // Event views: render-ready shapes — resolved day spans and formatted
  // labels.

  function eventView(raw) {
    var timed = !!raw.start.dateTime;
    var startWall = wall(timed ? raw.start.dateTime : raw.start.date);
    var endWall = wall(timed ? raw.end.dateTime : raw.end.date);

    var date = dayValue(startWall);
    var endDate;
    if (timed) {
      // An event ending exactly at midnight doesn't occupy that day.
      endDate = dayValue(endWall);
      if (endWall.h === 0 && endWall.min === 0) endDate -= DAY;
    } else {
      // All-day end dates are exclusive, so the inclusive last day is the
      // day before (clamped for zero-length events).
      endDate = dayValue(endWall) - DAY;
    }
    endDate = Math.max(endDate, date);

    var url = null;
    if (raw.url && /^https?:\/\//.test(raw.url)) url = raw.url;

    var formattedStartsAt = timed
      ? longDate(date) + " at " + hour12(startWall.h) + ":" + pad(startWall.min) + " " + (startWall.h < 12 ? "AM" : "PM")
      : longDate(date);

    var formattedEndsAt = null;
    if (timed) {
      formattedEndsAt = dayValue(endWall) === date
        ? clockTime(endWall)
        : longDate(dayValue(endWall)) + " at " + clockTime(endWall);
    } else if (endDate > date) {
      formattedEndsAt = longDate(endDate);
    }

    var startParts = dayParts(date);
    return {
      title: raw.title,
      location: raw.location || "",
      source: raw.source || "",
      url: url,
      date: date,
      endDate: endDate,
      iso: timed ? raw.start.dateTime : raw.start.date,
      formattedStartsAt: formattedStartsAt,
      formattedEndsAt: formattedEndsAt,
      formattedTime: timed
        ? hour12(startWall.h) + (startWall.min === 0 ? "" : ":" + pad(startWall.min)) + (startWall.h < 12 ? "am" : "pm")
        : null,
      formattedMonth: MONTHS[startParts.mo - 1] + " " + startParts.y
    };
  }

  // The source an event's stored value maps back to; events without one (or
  // with an unrecognized one) are community submissions.
  function sourceFor(value) {
    for (var i = 0; i < sources.length; i++) {
      if (sources[i].value === value) return sources[i];
    }
    return sources[0];
  }

  // ---------------------------------------------------------------------
  // DOM building. Everything event-derived goes through textContent, never
  // markup.

  function el(tag, attrs, children) {
    var node = document.createElement(tag);
    if (attrs) {
      for (var key in attrs) {
        if (key === "text") node.textContent = attrs[key];
        else if (attrs[key] !== null && attrs[key] !== undefined) node.setAttribute(key, attrs[key]);
      }
    }
    (children || []).forEach(function (child) { node.appendChild(child); });
    return node;
  }

  // The title link/span shared by the calendar's bars and day entries.
  function calendarLink(view) {
    var tooltip = view.title + " — " + view.formattedStartsAt;
    return view.url
      ? el("a", { href: view.url, target: "_blank", rel: "noopener noreferrer", title: tooltip, text: view.title })
      : el("span", { title: tooltip, text: view.title });
  }

  function renderList(views) {
    var fragment = document.createDocumentFragment();
    var month = null;
    var listNode = null;

    views.forEach(function (view) {
      if (view.formattedMonth !== month) {
        month = view.formattedMonth;
        listNode = el("ul", { class: "events" });
        fragment.appendChild(
          el("details", { class: "event-month", open: "" }, [
            el("summary", { class: "event-month-title" }, [
              el("h3", { text: month }),
              el("span", { class: "event-month-toggle", "aria-hidden": "true" })
            ]),
            listNode
          ])
        );
      }

      var time = el("time", { class: "event-time", datetime: view.iso, text: view.formattedStartsAt });
      if (view.formattedEndsAt) time.textContent += " – " + view.formattedEndsAt;

      var title = el("h3", { class: "event-title" }, [
        view.url
          ? el("a", { href: view.url, target: "_blank", rel: "noopener noreferrer", text: view.title })
          : document.createTextNode(view.title)
      ]);

      var item = el("li", null, [time, title]);
      if (view.location) item.appendChild(el("p", { class: "event-location", text: view.location }));
      listNode.appendChild(item);
    });

    return fragment;
  }

  // ---------------------------------------------------------------------
  // The month-by-month calendar. Multi-day events render as bars spanning
  // the days they cover, so each week assigns them lanes; each day cell gets
  // its lane slots followed by the day's single-day events, collapsing into
  // "+N more" past MAX_LINES.

  function buildMonths(views, today, truncated) {
    if (!views.length) return [];

    var first = monthOf(views.reduce(function (min, v) { return Math.min(min, v.date); }, Infinity));
    first = Math.max(first, monthOf(today));
    var last = views.reduce(function (max, v) { return Math.max(max, monthOf(v.endDate)); }, -Infinity);

    if (truncated) {
      // The months from the last fetched start onward would render
      // incomplete; drop them unless that would drop the whole calendar.
      var complete = shiftMonth(monthOf(views.reduce(function (max, v) { return Math.max(max, v.date); }, -Infinity)), -1);
      if (complete >= first) last = complete;
    }

    var months = [];
    for (var month = first; month <= last; month = shiftMonth(month, 1)) {
      var monthLast = shiftMonth(month, 1) - DAY;
      months.push({
        first: month,
        last: monthLast,
        views: views.filter(function (v) { return v.date <= monthLast && v.endDate >= month; })
      });
    }
    return months;
  }

  function monthWeeks(month, today) {
    // Earlier-starting (then longer) bars claim lower lanes so the stacking
    // is stable across the weeks.
    var multiDay = month.views
      .filter(function (v) { return v.endDate > v.date; })
      .sort(function (a, b) { return (a.date - b.date) || ((a.date - a.endDate) - (b.date - b.endDate)); });
    var singles = {};
    month.views.forEach(function (v) {
      if (v.endDate > v.date) return;
      (singles[v.date] = singles[v.date] || []).push(v);
    });

    var days = [];
    var leading = (dayParts(month.first).wd + 6) % 7; // Monday-aligned
    for (var i = 0; i < leading; i++) days.push(null);
    for (var day = month.first; day <= month.last; day += DAY) days.push(day);
    while (days.length % 7 !== 0) days.push(null);

    var weeks = [];
    for (var w = 0; w < days.length; w += 7) {
      var week = days.slice(w, w + 7);
      var dates = week.filter(function (d) { return d !== null; });
      var from = dates[0];
      var to = dates[dates.length - 1];

      // Give each bar overlapping this week the lowest lane that's free
      // from its first visible day on.
      var lanes = [];
      var assigned = [];
      multiDay.forEach(function (view) {
        if (view.date > to || view.endDate < from) return;
        var start = Math.max(view.date, from);
        var lane = 0;
        while (lane < lanes.length && lanes[lane] >= start) lane++;
        lanes[lane] = Math.min(view.endDate, to);
        assigned.push({ view: view, lane: lane, start: start });
      });

      weeks.push(week.map(function (date) {
        if (date === null) return { date: null, spans: [], events: [] };

        var spans = [];
        assigned.forEach(function (entry) {
          if (entry.view.date > date || date > entry.view.endDate) return;
          var runEnd = Math.min(entry.view.endDate, to);
          var label = date === entry.start;
          spans[entry.lane] = {
            view: entry.view,
            label: label,
            continuesLeft: entry.view.date < date,
            continuesRight: entry.view.endDate > (label ? runEnd : date),
            days: label ? (runEnd - date) / DAY + 1 : null
          };
        });

        return { date: date, today: date === today, spans: spans, events: singles[date] || [] };
      }));
    }
    return weeks;
  }

  function spanClasses(span) {
    var classes = ["cal-span"];
    if (span.label) classes.push("cal-span-label");
    if (span.continuesLeft) classes.push("cal-span-left");
    if (span.continuesRight) classes.push("cal-span-right");
    return classes.join(" ");
  }

  function renderCalendar(views, listHref) {
    var today = todayValue();
    var fragment = document.createDocumentFragment();

    buildMonths(views, today, views.length >= MAX_RESULTS).forEach(function (month) {
      var monthName = dayParts(month.first);
      var head = el("tr", null, ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"].map(function (day) {
        return el("th", { scope: "col", text: day });
      }));

      var body = el("tbody");
      monthWeeks(month, today).forEach(function (week) {
        var row = el("tr");
        week.forEach(function (cell) {
          if (cell.date === null) {
            row.appendChild(el("td", { class: "cal-day cal-day-blank" }));
            return;
          }

          var td = el("td", { class: "cal-day" + (cell.today ? " cal-today" : "") }, [
            el("span", { class: "cal-day-num", text: String(dayParts(cell.date).d) })
          ]);

          for (var lane = 0; lane < cell.spans.length; lane++) {
            var span = cell.spans[lane];
            if (!span) {
              td.appendChild(el("p", { class: "cal-span cal-span-spacer", "aria-hidden": "true", text: " " }));
            } else if (span.label) {
              td.appendChild(el("p", {
                class: spanClasses(span),
                style: "--span-days: " + span.days + "; --event-color: " + sourceFor(span.view.source).color
              }, [calendarLink(span.view)]));
            } else {
              td.appendChild(el("p", {
                class: spanClasses(span),
                style: "--event-color: " + sourceFor(span.view.source).color,
                "aria-hidden": "true",
                text: " "
              }));
            }
          }

          // The single-day events that fit beside the multi-day lanes; when
          // they don't all fit, the last row becomes the "+N more" link.
          var available = Math.max(MAX_LINES - cell.spans.length, 0);
          var visible = cell.events.length > available ? cell.events.slice(0, Math.max(available - 1, 0)) : cell.events;
          visible.forEach(function (view) {
            var entry = el("p", { class: "cal-event", style: "--event-color: " + sourceFor(view.source).color });
            if (view.formattedTime) entry.appendChild(el("span", { class: "cal-event-time", text: view.formattedTime }));
            entry.appendChild(calendarLink(view));
            td.appendChild(entry);
          });

          var overflow = cell.events.length - visible.length;
          if (overflow > 0) {
            td.appendChild(el("p", { class: "cal-more" }, [
              el("a", { href: listHref, "data-more-link": "", text: "+" + overflow + " more" })
            ]));
          }

          row.appendChild(td);
        });
        body.appendChild(row);
      });

      fragment.appendChild(el("div", { class: "cal-scroll" }, [
        el("table", { class: "cal-month" }, [
          el("caption", { class: "cal-month-title", text: MONTHS[monthName.mo - 1] + " " + monthName.y }),
          el("thead", null, [head]),
          body
        ])
      ]));
    });

    return fragment;
  }

  // ---------------------------------------------------------------------
  // Filter state and interactions. Everything renders locally from the
  // fetched set; only a search change re-fetches.

  var dropdown = filters.querySelector("[data-source-filter]");
  var options = Array.prototype.slice.call(filters.querySelectorAll(".source-option"));
  var badge = filters.querySelector("[data-source-count]");
  var applied = filters.querySelector("[data-applied]");
  var search = filters.querySelector("[data-search]");
  var views = Array.prototype.slice.call(filters.querySelectorAll("[data-view]"));
  var searchTimer = null;
  var fetchSequence = 0;
  var loadedQuery = null;
  var loadedViews = null; // null means the fetch failed (or hasn't happened)

  function selected() {
    return options.filter(function (option) {
      return option.getAttribute("aria-checked") === "true";
    });
  }

  function setChecked(option, value) {
    option.setAttribute("aria-checked", value ? "true" : "false");
  }

  function currentView() {
    var active = views.filter(function (option) {
      return option.getAttribute("aria-current") === "true";
    })[0];
    return active ? active.dataset.view : "list";
  }

  function setView(view) {
    views.forEach(function (option) {
      option.setAttribute("aria-current", option.dataset.view === view ? "true" : "false");
    });
    // The calendar view renders in the wide layout.
    document.body.classList.toggle("wide", view === "calendar");
  }

  function queryString(overrides) {
    var params = new URLSearchParams();

    var slugs = selected().map(function (option) { return option.dataset.source; });
    if (slugs.length) params.set("source", slugs.join(","));

    if (search && search.value.trim()) params.set("q", search.value.trim());

    var view = (overrides && overrides.view) || currentView();
    if (view === "calendar") params.set("view", "calendar");

    return params.toString();
  }

  function pageUrl(qs) {
    return qs ? window.location.pathname + "?" + qs : window.location.pathname;
  }

  function renderControls() {
    var chosen = selected();

    if (badge) {
      badge.textContent = String(chosen.length);
      badge.hidden = chosen.length === 0;
    }

    if (applied) {
      applied.querySelectorAll(".applied-chip").forEach(function (chip) { chip.remove(); });
      chosen.forEach(function (option) {
        var chip = document.createElement("a");
        chip.className = "applied-chip";
        chip.href = "#";
        chip.dataset.source = option.dataset.source;
        chip.setAttribute("aria-label", "Remove " + option.dataset.label + " filter");
        chip.textContent = option.dataset.label;
        chip.appendChild(el("span", { class: "applied-chip-x", "aria-hidden": "true", text: "×" }));
        applied.appendChild(chip);
      });
      applied.hidden = chosen.length === 0;
    }
  }

  function showError() {
    var error = document.querySelector("[data-error]");
    results.innerHTML = "";
    if (error) results.appendChild(error.content.cloneNode(true));
  }

  // Renders the fetched set through the current source filter and view.
  function renderResults() {
    if (loadedViews === null) {
      showError();
      return;
    }

    var slugs = selected().map(function (option) { return option.dataset.source; });
    var visible = loadedViews.filter(function (view) {
      return slugs.length === 0 || slugs.indexOf(sourceFor(view.source).slug) !== -1;
    });

    results.innerHTML = "";
    if (visible.length === 0) {
      results.appendChild(el("p", { class: "empty-state", text: "No upcoming events." }));
    } else if (currentView() === "calendar") {
      results.appendChild(renderCalendar(visible, pageUrl(queryString({ view: "list" }))));
    } else {
      results.appendChild(renderList(visible));
    }
  }

  // Fetches the events for the current search query, then renders. Stale
  // responses (a newer fetch has started) are dropped.
  function fetchAndRender() {
    var query = search && search.value.trim() ? search.value.trim() : "";
    var sequence = ++fetchSequence;

    var skeleton = document.querySelector('[data-skeleton="' + currentView() + '"]');
    results.innerHTML = "";
    if (skeleton) results.appendChild(skeleton.content.cloneNode(true));
    results.setAttribute("aria-busy", "true");

    var url = endpoint + (query ? (endpoint.indexOf("?") === -1 ? "?" : "&") + "q=" + encodeURIComponent(query) : "");
    fetch(url)
      .then(function (response) {
        if (!response.ok) throw new Error("status " + response.status);
        return response.json();
      })
      .then(function (payload) {
        if (sequence !== fetchSequence) return;
        loadedQuery = query;
        loadedViews = payload.events.map(eventView);
        renderResults();
      })
      .catch(function () {
        if (sequence !== fetchSequence) return;
        loadedQuery = query;
        loadedViews = null;
        showError();
      })
      .then(function () {
        if (sequence === fetchSequence) results.removeAttribute("aria-busy");
      });
  }

  // Re-renders after a control change, re-fetching only when the search
  // query differs from the loaded set's.
  function refresh() {
    var query = search && search.value.trim() ? search.value.trim() : "";
    if (loadedViews === null || query !== loadedQuery) {
      fetchAndRender();
    } else {
      renderResults();
    }
  }

  // Pushes the matching URL so the address bar reflects the filters and
  // back/forward works, then refreshes.
  function apply() {
    history.pushState(null, "", pageUrl(queryString()));
    renderControls();
    refresh();
  }

  function syncFromUrl() {
    var params = new URLSearchParams(window.location.search);
    var slugs = (params.get("source") || "").split(",");
    options.forEach(function (option) {
      setChecked(option, slugs.indexOf(option.dataset.source) !== -1);
    });
    if (search) search.value = params.get("q") || "";
    setView(params.get("view") === "calendar" ? "calendar" : "list");
    renderControls();
  }

  views.forEach(function (option) {
    option.addEventListener("click", function (event) {
      event.preventDefault();
      if (option.dataset.view === currentView()) return;
      setView(option.dataset.view);
      apply();
    });
  });

  options.forEach(function (option) {
    option.addEventListener("click", function (event) {
      event.preventDefault();
      setChecked(option, option.getAttribute("aria-checked") !== "true");
      apply();
    });
  });

  if (applied) {
    applied.addEventListener("click", function (event) {
      var chip = event.target.closest(".applied-chip");
      if (chip) {
        event.preventDefault();
        options.forEach(function (option) {
          if (option.dataset.source === chip.dataset.source) setChecked(option, false);
        });
        apply();
      }
    });
  }

  var selectAll = filters.querySelector("[data-select-all]");
  if (selectAll) {
    selectAll.addEventListener("click", function (event) {
      event.preventDefault();
      options.forEach(function (option) { setChecked(option, true); });
      apply();
    });
  }

  var clearSources = filters.querySelector("[data-clear-sources]");
  if (clearSources) {
    clearSources.addEventListener("click", function (event) {
      event.preventDefault();
      options.forEach(function (option) { setChecked(option, false); });
      apply();
    });
  }

  if (search) {
    search.addEventListener("input", function () {
      window.clearTimeout(searchTimer);
      searchTimer = window.setTimeout(apply, 250);
    });
  }

  var form = filters.querySelector(".filter-search-form");
  if (form) {
    form.addEventListener("submit", function (event) {
      event.preventDefault();
      window.clearTimeout(searchTimer);
      apply();
    });
  }

  // "+N more" links inside the calendar switch to the list view in place.
  results.addEventListener("click", function (event) {
    var link = event.target.closest("[data-more-link]");
    if (link) {
      event.preventDefault();
      setView("list");
      apply();
    }
  });

  // Close the dropdown on an outside click or Escape (native <details> only
  // closes via its own summary otherwise).
  if (dropdown) {
    document.addEventListener("click", function (event) {
      if (dropdown.open && !dropdown.contains(event.target)) dropdown.open = false;
    });
    dropdown.addEventListener("keydown", function (event) {
      if (event.key === "Escape") dropdown.open = false;
    });
  }

  window.addEventListener("popstate", function () {
    syncFromUrl();
    refresh();
  });

  syncFromUrl();
  fetchAndRender();
})();
