# frozen_string_literal: true

require "cgi/escape"

module NeedhamCircle
  module Sync
    # Needham Observer runs The Events Calendar (Tribe), but authors events in
    # the block editor, so it delegates to a Tribe fetcher with two field
    # cleaners: titles arrive HTML-entity-encoded, and descriptions wrap the
    # prose in Tribe's rendered blocks (a leading schedule widget, then — after
    # the prose — an "Add to calendar" subscribe dropdown, event-meta, and venue
    # block) that must be stripped before reducing to text.
    class NeedhamObserver
      Sync.register(self)

      ENDPOINT = "https://needhamobserver.com/wp-json/tribe/events/v1/events"

      SCHEDULE_BLOCK = %r{<div\b[^>]*tribe-events-schedule\b.*?</div>}mi
      TRAILING_BLOCKS = %r{<div\b[^>]*tribe-block__events-link\b.*\z}mi

      #: (?fetch_page: ^(Integer) -> Hash[String, untyped]?, ?logger: Logger?) -> void
      def initialize(**options)
        @tribe =
          Tribe.new(
            source: Source::NO,
            endpoint: ENDPOINT,
            title: ->(raw) { CGI.unescapeHTML(raw.to_s) },
            description: method(:clean_description),
            **options
          )
      end

      #: () -> Source
      def source
        @tribe.source
      end

      #: () -> Array[Event]?
      def fetch_events
        @tribe.fetch_events
      end

      private

      #: (String? html) -> String
      def clean_description(html)
        return "" if html.nil? || html.empty?

        stripped = html.gsub(SCHEDULE_BLOCK, " ").sub(TRAILING_BLOCKS, "")
        Sync.html_to_text(stripped)
      end
    end
  end
end
