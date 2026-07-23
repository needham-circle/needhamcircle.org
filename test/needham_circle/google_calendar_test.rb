# frozen_string_literal: true

require "test_helper"

module NeedhamCircle
  class GoogleCalendarTest < Minitest::Test
    # EventView.for is the dispatch every listed event flows through: Google
    # sends start.date_time for timed events and start.date for all-day ones.
    def test_for_pairs_timed_events_with_the_date_time_formatter
      view =
        GoogleCalendar::EventView.for(
          google_event(date_time(Time.utc(2026, 7, 9, 18, 30)), date_time(Time.utc(2026, 7, 9, 20, 30)))
        )

      assert_equal Date.new(2026, 7, 9), view.date
      assert_equal Date.new(2026, 7, 9), view.end_date
      assert_equal "Thursday, July 9 at 6:30 PM", view.formatted_starts_at
    end

    def test_for_pairs_all_day_events_with_the_date_formatter
      view =
        GoogleCalendar::EventView.for(
          google_event(all_day(Date.new(2026, 7, 9)), all_day(Date.new(2026, 7, 12)))
        )

      assert_equal Date.new(2026, 7, 9), view.date
      # The exclusive all-day end date becomes the inclusive last day.
      assert_equal Date.new(2026, 7, 11), view.end_date
      assert_equal "Thursday, July 9", view.formatted_starts_at
      assert_equal "Saturday, July 11", view.formatted_ends_at
    end

    def test_for_raises_when_the_start_has_neither_kind
      blank = Google::Apis::CalendarV3::EventDateTime.new
      assert_raises(RuntimeError) do
        GoogleCalendar::EventView.for(google_event(blank, blank))
      end
    end

    def test_formatted_time_is_compact_and_drops_zero_minutes
      on_the_hour =
        GoogleCalendar::EventView.for(
          google_event(date_time(Time.utc(2026, 7, 9, 19, 0)), date_time(Time.utc(2026, 7, 9, 21, 0)))
        )
      half_past =
        GoogleCalendar::EventView.for(
          google_event(date_time(Time.utc(2026, 7, 9, 18, 30)), date_time(Time.utc(2026, 7, 9, 20, 30)))
        )

      assert_equal "7pm", on_the_hour.formatted_time
      assert_equal "6:30pm", half_past.formatted_time
    end

    def test_all_day_events_have_no_formatted_time
      view =
        GoogleCalendar::EventView.for(
          google_event(all_day(Date.new(2026, 7, 9)), all_day(Date.new(2026, 7, 10)))
        )

      assert_nil view.formatted_time
    end

    def test_timed_event_ending_exactly_at_midnight_does_not_occupy_that_day
      view =
        GoogleCalendar::EventView.for(
          google_event(date_time(Time.utc(2026, 7, 9, 18, 30)), date_time(Time.utc(2026, 7, 10, 0, 0)))
        )

      assert_equal Date.new(2026, 7, 9), view.end_date
    end

    private

    def google_event(starts, ends)
      Google::Apis::CalendarV3::Event.new(summary: "Event", start: starts, end: ends)
    end

    def date_time(time)
      Google::Apis::CalendarV3::EventDateTime.new(date_time: time)
    end

    def all_day(date)
      Google::Apis::CalendarV3::EventDateTime.new(date: date)
    end
  end
end
