# frozen_string_literal: true

require "test_helper"

module NeedhamCircle
  module Sync
    class VolanteFarmsTest < Minitest::Test
      # A fixed clock so the upcoming/past filter is deterministic. The cutoff
      # is a day before this, i.e. "2026-06-30 12:00:00" Eastern wall clock.
      NOW = Time.utc(2026, 7, 1, 12, 0, 0)

      def setup
        @calendar = FakeCalendar.new
      end

      def test_targets_volante_farms_source
        assert_equal Source::VF, VolanteFarms.new.source
      end

      def test_keeps_only_summer_concert_events
        sync =
          build_sync(
            payload(
              [
                event_payload(id: 1, title: "Summer Concert #2 - The Headliners"),
                event_payload(id: 2, title: "Free Summer Concert Series: The Cover Band"),
                event_payload(id: 3, title: "Wine Tasting"),
                event_payload(id: 4, title: "January Wine Sale")
              ]
            )
          )

        assert sync.call
        assert_equal %w[1 2], @calendar.upserts.map { |_, e| e.source_id }
      end

      def test_skips_past_seasons_but_keeps_just_ended_events
        sync =
          build_sync(
            payload(
              [
                event_payload(
                  id: 1,
                  title: "Free Summer Concert Series: The Tribute Act",
                  start: "2025-08-14 18:30:00",
                  ends: "2025-08-14 20:30:00"
                ),
                # Ended after the day-of-grace cutoff — still synced.
                event_payload(
                  id: 2,
                  title: "Summer Concert #1 - The Openers",
                  start: "2026-06-30 18:30:00",
                  ends: "2026-06-30 20:30:00"
                ),
                event_payload(id: 3, title: "Summer Concert #2 - The Headliners")
              ]
            )
          )

        assert sync.call
        assert_equal %w[2 3], @calendar.upserts.map { |_, e| e.source_id }
      end

      def test_skips_draft_events
        sync =
          build_sync(
            payload(
              [
                event_payload(id: 1, title: "Summer Concert #2 - The Headliners", draft: "1"),
                event_payload(id: 3, title: "Summer Concert #4 - The Soundchecks")
              ]
            )
          )

        assert sync.call
        assert_equal %w[3], @calendar.upserts.map { |_, e| e.source_id }
      end

      def test_fails_on_a_recurring_event_whose_series_is_live
        # A recurring row carries only its first occurrence, so even though
        # that occurrence is already past the cutoff, the live series must
        # fail the sync rather than be dropped as a past event.
        sync =
          build_sync(
            payload(
              [
                event_payload(
                  id: 1,
                  title: "Summer Concert #1 - The Openers",
                  start: "2026-06-04 18:30:00",
                  ends: "2026-06-04 20:30:00",
                  recurring: 1,
                  series_end: "2026-08-13 23:59:59"
                ),
                event_payload(id: 2, title: "Summer Concert #2 - The Headliners")
              ]
            )
          )

        refute sync.call
        assert_empty @calendar.upserts
      end

      def test_skips_a_recurring_event_whose_series_already_ended
        sync =
          build_sync(
            payload(
              [
                event_payload(
                  id: 1,
                  title: "Free Summer Concert Series: The Cover Band",
                  start: "2025-07-10 18:30:00",
                  ends: "2025-07-10 20:30:00",
                  recurring: 1,
                  series_end: "2025-08-14 23:59:59"
                ),
                event_payload(id: 2, title: "Summer Concert #2 - The Headliners")
              ]
            )
          )

        assert sync.call
        assert_equal %w[2], @calendar.upserts.map { |_, e| e.source_id }
      end

      def test_fails_when_no_title_in_the_feed_matches_the_series
        sync =
          build_sync(
            payload(
              [
                event_payload(id: 1, title: "Wine Tasting"),
                event_payload(id: 2, title: "Concerts on the Patio 2027")
              ]
            )
          )

        refute sync.call
        assert_empty @calendar.upserts
      end

      def test_builds_event_from_feed_fields
        sync = build_sync(payload([event_payload(id: 56404, title: "Summer Concert #2 - The Headliners")]))

        assert sync.call
        event = @calendar.upserts[0][1]
        assert_equal "56404", event.source_id
        assert_equal "Summer Concert #2 - The Headliners", event.title
        assert_equal "The Headliners take the stage.\nFREE EVENT!", event.description
        assert_equal "Volante Farms Ice Cream Patio", event.location
        assert_equal "2026-07-09T18:30:00", event.start_at
        assert_equal "2026-07-09T20:30:00", event.end_at
        assert_equal "America/New_York", event.timezone
      end

      def test_links_external_url_when_present_else_calendar_page
        sync =
          build_sync(
            payload(
              [
                event_payload(id: 1, title: "Summer Concert #2 - The Headliners", url: "https://volantefarms.com/concerts"),
                event_payload(id: 2, title: "Summer Concert #3 - The Encores")
              ]
            )
          )

        assert sync.call
        assert_equal "https://volantefarms.com/concerts", @calendar.upserts[0][1].url
        assert_equal VolanteFarms::PAGE_URL, @calendar.upserts[1][1].url
      end

      def test_returns_false_when_fetch_yields_nil
        sync = build_sync(nil)
        refute sync.call
        assert_empty @calendar.upserts
      end

      def test_returns_false_when_api_reports_failure
        sync = build_sync({ "result" => "fail", "msg" => "Bad request call!" })
        refute sync.call
        assert_empty @calendar.upserts
      end

      private

      def build_sync(response)
        Runner.new(
          calendar: @calendar,
          calendar_id: "events-cal-id",
          fetcher: VolanteFarms.new(fetch: -> { response }, now: NOW)
        )
      end

      def payload(events)
        { "event_data" => events }
      end

      def event_payload(id:, title:, start: "2026-07-09 18:30:00", ends: "2026-07-09 20:30:00", draft: "0", recurring: 0, series_end: nil, url: "")
        {
          "event_id" => id,
          "event_title" => title,
          "start_date_time" => start,
          "end_date_time" => ends,
          "event_location" => "Volante Farms Ice Cream Patio",
          "event_details" => "<p><span>The Headliners take the stage.</span></p><p><br></p><p><strong>FREE EVENT!</strong></p>",
          "external_url" => url,
          "is_draft_event" => draft,
          "is_recurring" => recurring,
          "end_recurring_event" => series_end
        }
      end
    end
  end
end
