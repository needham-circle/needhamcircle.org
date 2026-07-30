# Needham Circle

The needhamcircle.org site.

| Page       | Source                     | Dynamic behavior                          |
| ---------- | -------------------------- | ----------------------------------------- |
| /          | index.md                   | —                                         |
| /about     | about.md                   | —                                         |
| /resources | resources.md + _data       | —                                         |
| /events    | events.md + js/events.js   | live fetch from ListEvents; filters/search/calendar render client-side |
| /submit    | submit.md + js/forms.js    | JSON POST to CreateSubmission             |
| /contact   | contact.md + js/forms.js   | JSON POST to SendContact                  |

The function URLs live in `_config.yml` (`events_endpoint`, `submit_endpoint`,
`contact_endpoint`) — fill them in after deploying the functions.

## Development

Terminal 1 — the functions devserver, from a checkout of
needham-circle/functions (see its README for the env vars):

```
cd ../functions
PORT=8081 go run ./cmd/devserver
```

Terminal 2 — the site, pointed at it via _config_local.yml:

```
bundle install
bundle exec jekyll serve --port 4000 --config _config.yml,_config_local.yml
```

Then open http://localhost:4000.
