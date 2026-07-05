# frozen_string_literal: true

require "test_helper"

module NeedhamCircle
  module Sync
    class NeedhamSchoolsArtsTest < Minitest::Test
      def setup
        @calendar = FakeCalendar.new
      end

      def test_targets_schools_arts_source
        assert_equal Source::NPSA, NeedhamSchoolsArts.new.source
      end

      def test_maps_modern_events_response
        sync = build_sync(
          "d" => {
            "events" => [
              {
                "eventID" => 85063803,
                "name" => "Great Hall Concert Series",
                "description" => "<p>An evening of music</p>",
                "location" => "Powers Hall Needham MA",
                "localStartDate" => "2026-09-19 19:30:00",
                "localEndDate" => "2026-09-19 20:30:00"
              }
            ]
          }
        )

        assert sync.call
        event = @calendar.upserts[0][1]
        assert_equal "85063803", event.source_id
        assert_equal "Great Hall Concert Series", event.title
        assert_equal "An evening of music", event.description
        assert_equal "Powers Hall Needham MA", event.location
        assert_equal "2026-09-19T19:30:00", event.start_at
        assert_equal "2026-09-19T20:30:00", event.end_at
        assert_equal "America/New_York", event.timezone
      end

      def test_skips_events_without_a_start
        sync = build_sync(
          "d" => { "events" => [{ "eventID" => 1, "name" => "TBD", "localStartDate" => "" }] }
        )

        assert sync.call
        assert_empty @calendar.upserts
      end

      def test_returns_false_when_fetch_yields_nil
        sync = build_sync(nil)
        refute sync.call
        assert_empty @calendar.upserts
      end

      private

      def build_sync(payload)
        Runner.new(
          calendar: @calendar,
          calendar_id: "events-cal-id",
          fetcher: NeedhamSchoolsArts.new(fetch: -> { payload })
        )
      end
    end
  end
end
