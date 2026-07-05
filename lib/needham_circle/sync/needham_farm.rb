# frozen_string_literal: true

require "json"
require "time"

module NeedhamCircle
  module Sync
    # Needham Farm runs on Wix using the Wix Events app, which has no public
    # feed. So we drive the same viewer API the events widget uses: fetch a
    # short-lived per-site "instance" token for the Events app, then page through
    # its events query endpoint with that token as the bearer credential.
    #
    # This is an undocumented, client-facing API — expect it to be brittle and
    # to need attention if Wix changes the endpoints or token flow.
    class NeedhamFarm
      Sync.register(self)

      HOST = "https://www.needhamfarm.org"

      # The Wix Events app's fixed appDefinitionId; the access-tokens response
      # keys each app's instance token by this id.
      EVENTS_APP_ID = "140603ad-af8d-84a5-2c80-a0f60cb47351"
      ACCESS_TOKENS_URL = "#{HOST}/_api/v1/access-tokens"
      EVENTS_QUERY_URL = "#{HOST}/_api/wix-events-web/v2/events/query"
      PER_PAGE = 50

      # Wix returns UTC instants (trailing "Z"), so we re-emit them as UTC ISO
      # and let Google apply America/New_York for display, as with the Rotary
      # feed. The Wix query returns past events too, so we drop ended ones.
      TIMEZONE = "America/New_York"

      #: (?fetch_page: ^(Integer) -> Hash[String, untyped]?, ?now: Time?, ?logger: Logger?) -> void
      def initialize(fetch_page: nil, now: nil, logger: nil)
        @fetch_page = fetch_page || method(:fetch_page_from_api)
        @now = now
        @logger = logger
      end

      #: () -> Source
      def source
        Source::NF
      end

      #: () -> Array[Event]?
      def fetch_events
        now = @now || Time.now
        events = []
        offset = 0
        loop do
          payload = @fetch_page.call(offset)
          return nil if payload.nil?

          page = payload["events"] || []
          page.each do |raw|
            next if raw["status"] == "CANCELED"
            event = build_event(raw)
            events << event if event && upcoming?(event, now)
          end

          meta = payload["pagingMetadata"] || {}
          total = meta["total"]
          count = meta["count"] || page.size
          offset += count
          # Stop at the end of the results, and defensively when a page makes no
          # progress or omits the total, so a malformed response can't spin here.
          break if page.empty? || count.zero? || total.nil? || offset >= total
        end
        events
      end

      private

      #: (Integer offset) -> Hash[String, untyped]?
      def fetch_page_from_api(offset)
        instance = instance_token
        return nil if instance.nil?

        body = JSON.generate("query" => { "paging" => { "limit" => PER_PAGE, "offset" => offset } })
        Sync::HTTP.post_json(EVENTS_QUERY_URL, body, { "Authorization" => instance }, logger: @logger)
      end

      # The Wix Events app's instance token, good for the life of this run.
      #: () -> String?
      def instance_token
        @instance_token ||= fetch_instance_token
      end

      #: () -> String?
      def fetch_instance_token
        # This viewer API is undocumented and brittle, so guard each level of
        # the response shape rather than trusting it: Hash#dig would still raise
        # if `apps` or its entry came back as a non-Hash.
        data = Sync::HTTP.get_json(ACCESS_TOKENS_URL, logger: @logger)
        apps = data["apps"] if data.is_a?(Hash)
        app = apps[EVENTS_APP_ID] if apps.is_a?(Hash)
        token = app["instance"] if app.is_a?(Hash)
        log("access-tokens response had no Wix Events instance") if token.nil?
        token
      end

      #: (Hash[String, untyped] raw) -> Event?
      def build_event(raw)
        config = raw.dig("scheduling", "config") || {}
        start_at = format_time(config["startDate"])
        return nil if start_at.nil? # scheduling TBD — can't place it on a calendar

        Event.new(
          source_id: raw.fetch("id").to_s,
          title: raw["title"].to_s,
          description: format_description(raw),
          location: format_location(raw["location"]),
          url: event_url(raw),
          start_at: start_at,
          end_at: format_time(config["endDate"]),
          timezone: TIMEZONE
        )
      end

      # Prefer the rich "about" body (HTML); fall back to the plain-text summary.
      #: (Hash[String, untyped] raw) -> String
      def format_description(raw)
        about = Sync.html_to_text(raw["about"])
        about.empty? ? raw["description"].to_s.strip : about
      end

      #: (Hash[String, untyped]? location) -> String
      def format_location(location)
        return "" if location.nil?

        if location["type"] == "ONLINE"
          name = location["name"].to_s.strip
          name.empty? ? "Online" : name
        else
          address = location["address"].to_s.strip
          address.empty? ? location["name"].to_s.strip : address
        end
      end

      #: (Hash[String, untyped] raw) -> String
      def event_url(raw)
        page = raw["eventPageUrl"] || {}
        "#{page["base"]}#{page["path"]}"
      end

      # Keep events whose end (or start, when the end is hidden) is still ahead.
      #: (Event event, Time now) -> bool
      def upcoming?(event, now)
        Time.iso8601(event.end_at || event.start_at) >= now
      end

      # Wix hands back UTC instants ("2026-06-15T15:00:00Z"). Normalize to the
      # same UTC ISO shape so Google reads the absolute instant.
      #: (String? iso) -> String?
      def format_time(iso)
        return nil if iso.nil? || iso.empty?
        Time.iso8601(iso).utc.strftime("%Y-%m-%dT%H:%M:%SZ")
      end

      #: (String message) -> void
      def log(message)
        @logger&.error("Sync::NeedhamFarm #{message}")
      end
    end
  end
end
