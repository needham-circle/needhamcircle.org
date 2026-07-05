# frozen_string_literal: true

module NeedhamCircle
  module Sync
    # LWV-Needham runs The Events Calendar (Tribe) with a plain REST feed, so it
    # delegates entirely to a configured Tribe fetcher.
    class Lwv
      Sync.register(self)

      ENDPOINT = "https://lwv-needham.org/wp-json/tribe/events/v1/events"

      #: (?fetch_page: ^(Integer) -> Hash[String, untyped]?, ?logger: Logger?) -> void
      def initialize(**options)
        @tribe = Tribe.new(source: Source::LWV, endpoint: ENDPOINT, **options)
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
