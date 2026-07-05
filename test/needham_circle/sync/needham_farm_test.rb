# frozen_string_literal: true

require "test_helper"

module NeedhamCircle
  module Sync
    class NeedhamFarmTest < Minitest::Test
      # A fixed clock so the upcoming/past filter is deterministic.
      NOW = Time.utc(2026, 7, 1, 12, 0, 0)

      def setup
        @calendar = FakeCalendar.new
      end

      def test_inserts_upcoming_events
        sync =
          build_sync(
            pages: [
              page(
                [event_payload(id: "a", title: "First"), event_payload(id: "b", title: "Second")]
              )
            ]
          )

        assert sync.call
        assert_equal 2, @calendar.upserts.size
        assert_equal "First", @calendar.upserts[0][1].title
        assert_equal "Second", @calendar.upserts[1][1].title
      end

      def test_updates_when_source_id_matches_existing
        @calendar.existing = { "a" => "google-evt-9" }
        sync = build_sync(pages: [page([event_payload(id: "a", title: "Updated")])])

        assert sync.call
        assert_equal "google-evt-9", @calendar.upserts[0][0]
        assert_equal "Updated", @calendar.upserts[0][1].title
      end

      def test_skips_past_and_canceled_events
        sync =
          build_sync(
            pages: [
              page(
                [
                  event_payload(id: "future", start: "2026-08-01T15:00:00Z"),
                  event_payload(id: "past", start: "2024-06-15T15:00:00Z", ends: "2024-06-15T17:00:00Z"),
                  event_payload(id: "canceled", status: "CANCELED")
                ]
              )
            ]
          )

        assert sync.call
        assert_equal %w[future], @calendar.upserts.map { |_, e| e.source_id }
      end

      def test_keeps_event_whose_end_is_still_ahead
        # Started before `now` but not yet over — still upcoming.
        sync =
          build_sync(
            pages: [
              page([event_payload(id: "ongoing", start: "2026-07-01T11:00:00Z", ends: "2026-07-01T18:00:00Z")])
            ]
          )

        assert sync.call
        assert_equal %w[ongoing], @calendar.upserts.map { |_, e| e.source_id }
      end

      def test_paginates_by_offset_until_total_reached
        sync =
          build_sync(
            pages: [
              page([event_payload(id: "a")], offset: 0, total: 2),
              page([event_payload(id: "b")], offset: 1, total: 2)
            ]
          )

        assert sync.call
        assert_equal %w[a b], @calendar.upserts.map { |_, e| e.source_id }
      end

      def test_returns_false_and_skips_upserts_on_list_error
        @calendar.list_error = Google::Apis::ServerError.new("boom")
        sync = build_sync(pages: [page([event_payload(id: "a")])])

        refute sync.call
        assert_empty @calendar.upserts
      end

      def test_returns_false_when_fetch_yields_nil
        sync = build_sync(pages: [nil])
        refute sync.call
        assert_empty @calendar.upserts
      end

      def test_returns_false_when_any_upsert_fails
        @calendar.upsert_error = Google::Apis::ServerError.new("nope")
        sync = build_sync(pages: [page([event_payload(id: "a")])])

        refute sync.call
        assert_equal 1, @calendar.upserts.size
      end

      def test_emits_utc_times_and_iana_zone
        sync = build_sync(pages: [page([event_payload(id: "a", start: "2026-08-01T15:00:00Z", ends: "2026-08-01T17:30:00Z")])])

        assert sync.call
        event = @calendar.upserts[0][1]
        assert_equal "2026-08-01T15:00:00Z", event.start_at
        assert_equal "2026-08-01T17:30:00Z", event.end_at
        assert_equal "America/New_York", event.timezone
      end

      def test_prefers_about_body_then_falls_back_to_description
        sync =
          build_sync(
            pages: [
              page(
                [
                  event_payload(id: "rich", about: "<p>Hello <strong>world</strong></p>", description: "ignored"),
                  event_payload(id: "plain", about: "", description: "Plain summary")
                ]
              )
            ]
          )

        assert sync.call
        assert_equal "Hello world", @calendar.upserts[0][1].description
        assert_equal "Plain summary", @calendar.upserts[1][1].description
      end

      def test_formats_venue_and_online_locations
        sync =
          build_sync(
            pages: [
              page(
                [
                  event_payload(id: "venue", location: { "type" => "VENUE", "name" => "Farm", "address" => "145 Pine St, Needham, MA" }),
                  event_payload(id: "online", location: { "type" => "ONLINE", "name" => "Zoom" })
                ]
              )
            ]
          )

        assert sync.call
        assert_equal "145 Pine St, Needham, MA", @calendar.upserts[0][1].location
        assert_equal "Zoom", @calendar.upserts[1][1].location
      end

      def test_builds_event_page_url
        sync = build_sync(pages: [page([event_payload(id: "a")])])

        assert sync.call
        assert_equal "https://www.needhamfarm.org/event-details-registration/a", @calendar.upserts[0][1].url
      end

      def test_targets_needham_farm_source
        assert_equal Source::NF, NeedhamFarm.new.source
      end

      private

      def build_sync(pages:)
        queue = pages.dup
        Runner.new(
          calendar: @calendar,
          calendar_id: "events-cal-id",
          fetcher: NeedhamFarm.new(fetch_page: ->(_offset) { queue.shift }, now: NOW)
        )
      end

      def page(events, offset: 0, total: nil)
        { "events" => events, "pagingMetadata" => { "count" => events.size, "offset" => offset, "total" => total || events.size } }
      end

      def event_payload(id:, status: "SCHEDULED", start: "2026-08-01T15:00:00Z", ends: nil, **overrides)
        {
          "id" => id,
          "title" => "Event #{id}",
          "status" => status,
          "about" => "",
          "description" => "Description #{id}",
          "location" => { "type" => "VENUE", "name" => "Farm", "address" => "145 Pine St, Needham, MA" },
          "eventPageUrl" => { "base" => "https://www.needhamfarm.org", "path" => "/event-details-registration/#{id}" },
          "scheduling" => { "config" => { "startDate" => start, "endDate" => ends } }
        }.merge(overrides.transform_keys(&:to_s))
      end
    end
  end
end
