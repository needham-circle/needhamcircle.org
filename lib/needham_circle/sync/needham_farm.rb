# frozen_string_literal: true

require "json"
require "net/http"
require "time"
require "uri"

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
          offset += meta["count"] || page.size
          break if page.empty? || offset >= (meta["total"] || offset)
        end
        events
      end

      private

      #: (Integer offset) -> Hash[String, untyped]?
      def fetch_page_from_api(offset)
        instance = instance_token
        return nil if instance.nil?

        body = JSON.generate("query" => { "paging" => { "limit" => PER_PAGE, "offset" => offset } })
        response = http_post(EVENTS_QUERY_URL, body, "Authorization" => instance)
        return nil if response.nil?

        JSON.parse(response)
      rescue StandardError => error
        log("events query offset=#{offset} raised: #{error.class}: #{error.message}")
        nil
      end

      # The Wix Events app's instance token, good for the life of this run.
      #: () -> String?
      def instance_token
        @instance_token ||=
          begin
            response = http_get(ACCESS_TOKENS_URL)
            app = response && (JSON.parse(response)["apps"] || {})[EVENTS_APP_ID]
            token = app && app["instance"]
            log("access-tokens response had no Wix Events instance") if token.nil?
            token
          rescue StandardError => error
            log("access-tokens fetch raised: #{error.class}: #{error.message}")
            nil
          end
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

      #: (String url, ?Hash[String, String] headers) -> String?
      def http_get(url, headers = {})
        http_request(url, Net::HTTP::Get.new(URI(url).request_uri), headers)
      end

      #: (String url, String body, ?Hash[String, String] headers) -> String?
      def http_post(url, body, headers = {})
        request = Net::HTTP::Post.new(URI(url).request_uri)
        request.body = body
        request["Content-Type"] = "application/json"
        http_request(url, request, headers)
      end

      #: (String url, Net::HTTPRequest request, Hash[String, String] headers) -> String?
      def http_request(url, request, headers)
        uri = URI(url)
        request["User-Agent"] = USER_AGENT
        headers.each { |name, value| request[name] = value }

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = 10
        http.read_timeout = 30

        response = http.request(request)
        return response.body if response.is_a?(Net::HTTPSuccess)

        log("#{request.method} #{uri.path} returned status #{response.code}")
        nil
      end

      #: (String message) -> void
      def log(message)
        @logger&.error("Sync::NeedhamFarm #{message}")
      end
    end
  end
end
