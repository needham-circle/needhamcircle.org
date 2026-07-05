# frozen_string_literal: true

require "cgi/escape"

module NeedhamCircle
  module Sync
    # Needham History Center runs The Events Calendar (Tribe). Its descriptions
    # are plain HTML, but its titles arrive HTML-entity-encoded, so it delegates
    # to a Tribe fetcher with just a title-decoding cleaner.
    class NeedhamHistory
      Sync.register(self)

      ENDPOINT = "https://needhamhistory.org/wp-json/tribe/events/v1/events"

      #: (?fetch_page: ^(Integer) -> Hash[String, untyped]?, ?logger: Logger?) -> void
      def initialize(**options)
        @tribe =
          Tribe.new(
            source: Source::NH,
            endpoint: ENDPOINT,
            title: ->(raw) { CGI.unescapeHTML(raw.to_s) },
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
    end
  end
end
