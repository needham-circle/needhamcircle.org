# frozen_string_literal: true

module NeedhamCircle
  module Sync
    # Green Needham runs The Events Calendar (Tribe) on a WordPress install under
    # /blog, so its REST events endpoint lives beneath that path. The feed is
    # otherwise plain, so it delegates entirely to a configured Tribe fetcher.
    class GreenNeedham
      Sync.register(self)

      ENDPOINT = "https://www.greenneedham.org/blog/wp-json/tribe/events/v1/events"

      #: (?fetch_page: ^(Integer) -> Hash[String, untyped]?, ?logger: Logger?) -> void
      def initialize(**options)
        @tribe = Tribe.new(source: Source::GN, endpoint: ENDPOINT, **options)
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
