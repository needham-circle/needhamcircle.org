---
title: "Needham Circle — Resources"
description: "Community resources for Needham: town offices, affinity groups, nonprofits, and parks."
permalink: /resources
wide: true
---

<h2>Resources</h2>

{% for section in site.data.resources %}
  <section class="resource-section">
    <h3>{{ section.title }}</h3>
    <table class="resource-table">
      <thead>
        <tr>
          <th scope="col">{{ section.name_heading }}</th>
          <th scope="col">Description</th>
          <th scope="col">{{ section.contact_heading }}</th>
        </tr>
      </thead>
      <tbody>
        {% for entry in section.entries %}
          <tr>
            <th scope="row">{{ entry.name }}</th>
            <td data-label="Description">{{ entry.description }}</td>
            <td data-label="{{ section.contact_heading }}">
              {% if entry.href %}
                <a href="{{ entry.href }}" title="{{ entry.contact }}"{% if entry.external %} target="_blank" rel="noopener noreferrer"{% endif %}><span class="contact-label">{{ entry.label }}</span><span class="contact-value">{{ entry.contact }}</span></a>
              {% else %}
                {{ entry.contact }}
              {% endif %}
            </td>
          </tr>
        {% endfor %}
      </tbody>
    </table>
  </section>
{% endfor %}
