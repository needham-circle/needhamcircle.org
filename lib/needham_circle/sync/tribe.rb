# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module NeedhamCircle
  module Sync
    # Fetches and normalizes events from a WordPress "The Events Calendar"
    # (Tribe) REST endpoint. Several Needham sources run this same plugin and
    # differ only in their endpoint and how a couple of fields are cleaned, so
    # each such source injects a configured Tribe as its collaborator (see
    # Sync::Lwv, Sync::GreenNeedham, Sync::NeedhamObserver) rather than
    # re-implementing the pagination/HTTP/parsing.
    class Tribe
      PER_PAGE = 50

      # Tribe's `timezone` field is a fixed offset abbreviation (e.g. "UTC-5")
      # that doesn't track DST. Every Tribe source here is local to Needham, so
      # we hand Google an IANA zone and let it apply DST correctly.
      TIMEZONE = "America/New_York"

      # Default field cleaners. Titles pass through untouched; descriptions are
      # reduced from HTML to display text. A source with quirkier markup (e.g.
      # entity-encoded titles or Tribe block wrappers) supplies its own.
      IDENTITY = ->(raw) { raw.to_s }
      HTML_TO_TEXT = ->(raw) { Sync.html_to_text(raw) }

      #: (source: Source, endpoint: String, ?title: ^(String?) -> String, ?description: ^(String?) -> String, ?fetch_page: ^(Integer) -> Hash[String, untyped]?, ?logger: Logger?) -> void
      def initialize(source:, endpoint:, title: IDENTITY, description: HTML_TO_TEXT, fetch_page: nil, logger: nil)
        @source = source
        @endpoint = endpoint
        @title = title
        @description = description
        @fetch_page = fetch_page || method(:fetch_page_from_api)
        @logger = logger
      end

      #: () -> Source
      attr_reader :source

      #: () -> Array[Event]?
      def fetch_events
        events = []
        page = 1
        loop do
          payload = @fetch_page.call(page)
          return nil if payload.nil?

          (payload["events"] || []).each do |raw|
            events << build_event(raw)
          end

          total_pages = payload["total_pages"] || 1
          break if page >= total_pages
          page += 1
        end
        events
      end

      private

      #: (Integer page) -> Hash[String, untyped]?
      def fetch_page_from_api(page)
        uri = URI(@endpoint)
        uri.query =
          URI.encode_www_form(per_page: PER_PAGE, page: page, status: "publish")

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = 10
        http.read_timeout = 30

        response = http.get(uri.request_uri, { "User-Agent" => USER_AGENT })
        unless response.is_a?(Net::HTTPSuccess)
          log("fetch page=#{page} returned status #{response.code}")
          return nil
        end

        JSON.parse(response.body)
      rescue StandardError => error
        log("fetch page=#{page} raised: #{error.class}: #{error.message}")
        nil
      end

      #: (Hash[String, untyped] raw) -> Event
      def build_event(raw)
        Event.new(
          source_id: raw.fetch("id").to_s,
          title: @title.call(raw["title"]),
          description: @description.call(raw["description"]),
          location: format_location(raw["venue"]),
          url: raw["url"].to_s,
          start_at: format_time(raw["start_date"]),
          end_at: format_time(raw["end_date"]),
          timezone: TIMEZONE
        )
      end

      #: (Hash[String, untyped]? venue) -> String
      def format_location(venue)
        return "" if venue.nil? || venue.empty?

        [
          venue["venue"],
          venue["address"],
          venue["city"],
          venue["state"],
          venue["zip"]
        ].compact.reject { |part| part.to_s.strip.empty? }.join(", ")
      end

      # Tribe returns "2026-05-28 18:00:00" — Google wants ISO-ish with a "T".
      #: (String? string) -> String?
      def format_time(string)
        return nil if string.nil? || string.empty?
        string.sub(" ", "T")
      end

      #: (String message) -> void
      def log(message)
        @logger&.error("Sync::Tribe[#{@source.slug}] #{message}")
      end
    end
  end
end
