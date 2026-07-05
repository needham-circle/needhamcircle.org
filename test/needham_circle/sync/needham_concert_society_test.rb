# frozen_string_literal: true

require "test_helper"

module NeedhamCircle
  module Sync
    # A plain Tribe wrapper — the Tribe pipeline (pagination, parsing, timezone,
    # venue) is covered by the Tribe-backed source tests (e.g. LwvTest), so this
    # just confirms the wrapper targets the right source and delegates to Tribe.
    class NeedhamConcertSocietyTest < Minitest::Test
      def setup
        @calendar = FakeCalendar.new
      end

      def test_targets_needham_concert_society_source
        assert_equal Source::NCS, NeedhamConcertSociety.new.source
      end

      def test_delegates_to_tribe_and_upserts_events
        sync =
          Runner.new(
            calendar: @calendar,
            calendar_id: "events-cal-id",
            fetcher: NeedhamConcertSociety.new(fetch_page: ->(_page) { @page })
          )
        @page = {
          "events" => [
            {
              "id" => 1,
              "title" => "Orion Chamber Ensemble",
              "description" => "<p>Chamber <strong>music</strong></p>",
              "url" => "https://needhamconcertsociety.org/event/1",
              "start_date" => "2026-05-28 15:00:00",
              "end_date" => "2026-05-28 17:00:00",
              "timezone" => "UTC+0",
              "venue" => { "venue" => "Carter Memorial", "city" => "Needham" }
            }
          ],
          "total_pages" => 1
        }

        assert sync.call
        event = @calendar.upserts[0][1]
        assert_equal "Orion Chamber Ensemble", event.title
        assert_equal "Chamber music", event.description
        assert_equal "Carter Memorial, Needham", event.location
        assert_equal "2026-05-28T15:00:00", event.start_at
        # Tribe overrides the source's fixed-offset zone with an IANA one.
        assert_equal "America/New_York", event.timezone
      end
    end
  end
end
