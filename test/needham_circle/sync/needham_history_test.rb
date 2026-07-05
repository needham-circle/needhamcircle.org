# frozen_string_literal: true

require "test_helper"

module NeedhamCircle
  module Sync
    # A Tribe wrapper whose only quirk is entity-encoded titles. The Tribe
    # pipeline is covered by the Tribe-backed source tests (e.g. LwvTest), so
    # this confirms the source wiring and the title-decoding cleaner.
    class NeedhamHistoryTest < Minitest::Test
      def setup
        @calendar = FakeCalendar.new
      end

      def test_targets_needham_history_source
        assert_equal Source::NH, NeedhamHistory.new.source
      end

      def test_decodes_entity_encoded_titles_and_delegates
        sync =
          Runner.new(
            calendar: @calendar,
            calendar_id: "events-cal-id",
            fetcher: NeedhamHistory.new(fetch_page: ->(_page) { @page })
          )
        @page = {
          "events" => [
            {
              "id" => 1,
              "title" => "Crime of the Century: How the Brink&#8217;s Robbers Stole Millions",
              "description" => "<p>A talk with Stephanie Schorow.</p>",
              "url" => "https://needhamhistory.org/event/1",
              "start_date" => "2026-01-12 19:00:00",
              "end_date" => "2026-01-12 21:00:00",
              "timezone" => "America/New_York",
              "venue" => { "venue" => "Needham History Center", "city" => "Needham" }
            }
          ],
          "total_pages" => 1
        }

        assert sync.call
        event = @calendar.upserts[0][1]
        assert_equal "Crime of the Century: How the Brink’s Robbers Stole Millions", event.title
        assert_equal "A talk with Stephanie Schorow.", event.description
        assert_equal "Needham History Center, Needham", event.location
      end
    end
  end
end
