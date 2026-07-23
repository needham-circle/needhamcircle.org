# frozen_string_literal: true

require "date"

module NeedhamCircle
  # Lays events out for the month-by-month calendar view: one grid per month
  # an event touches, each a set of Monday-aligned week rows. Multi-day events
  # render as bars spanning the days they cover, so each week assigns them
  # lanes (a bar keeps its row across the week, and overlapping bars stack),
  # and each day cell receives its lane slots followed by the day's
  # single-day events.
  class MonthGrid
    # One lane slot of a multi-day bar within a day cell. The label renders on
    # the first day of the bar's run in each week and stretches across the
    # run's `days` cells; continues_left/right mark where the bar carries over
    # from before the label's cell or past the run (which may sit in another
    # week row or month grid). Continuation slots fill the run's remaining
    # cells underneath, with day-level continues flags for their corners.
    Span = Struct.new(:event, :label, :continues_left, :continues_right, :days, keyword_init: true) do
      # The segment's classes: the label variant stretches across its run (see
      # .cal-span-label), and each continuing edge squares off and bleeds over
      # the cell border.
      #: () -> String
      def css_classes
        classes = ["cal-span"]
        classes << "cal-span-label" if label
        classes << "cal-span-left" if continues_left
        classes << "cal-span-right" if continues_right
        classes.join(" ")
      end

    end

    # How many rows a day cell shows under its number (multi-day lanes plus
    # single-day events) before the last row collapses into "+N more". Keep
    # in step with .cal-day's height, which fits exactly this many rows.
    MAX_LINES = 4

    # A day cell: its date (nil for the padding around the month's edges),
    # whether it's today, the lane-indexed multi-day slots (each a Span, or
    # nil where a spacer keeps a higher lane's bar aligned), and the
    # single-day events listed below them.
    Cell = Struct.new(:date, :today, :spans, :events, keyword_init: true) do
      # The single-day events that fit beside the multi-day lanes; when they
      # don't all fit, the last row is reserved for the "+N more" link.
      #: () -> Array[GoogleCalendar::EventView]
      def visible_events
        available = [MAX_LINES - spans.length, 0].max
        events.length > available ? events.first([available - 1, 0].max) : events
      end

      #: () -> Integer
      def overflow_count
        events.length - visible_events.length
      end
    end

    # Grids for a contiguous run of months — from the first event's month
    # (clamped to today's, so an ongoing event doesn't resurrect a past
    # month) through the last event's end month, with gap months rendered
    # empty rather than skipped so the timeline reads continuously. When the
    # feed was `truncated` at the API's result cap, the months from the last
    # fetched start onward are dropped instead of rendered incomplete — a
    # month that looks complete but isn't would be worse than no month.
    #: (Array[GoogleCalendar::EventView] events, today: Date, ?truncated: bool) -> Array[MonthGrid]
    def self.build(events, today:, truncated: false)
      return [] if events.empty?

      first = [events.map { |event| month_of(event.date) }.min, month_of(today)].max
      last = events.map { |event| month_of(event.end_date) }.max

      if truncated
        complete = month_of(events.map(&:date).max) << 1
        # Keep the partial months only when dropping them would drop the
        # whole calendar.
        last = complete if complete >= first
      end

      months = []
      month = first
      while month <= last
        months << month
        month = month >> 1
      end

      months.map do |month_first|
        month_last = Date.new(month_first.year, month_first.month, -1)
        new(
          month_first,
          events.select { |event| event.date <= month_last && event.end_date >= month_first },
          today: today
        )
      end
    end

    #: (Date date) -> Date
    def self.month_of(date)
      Date.new(date.year, date.month, 1)
    end

    #: (Date first, Array[GoogleCalendar::EventView] events, today: Date) -> void
    def initialize(first, events, today:)
      @first = first
      @events = events
      @today = today
    end

    #: () -> String
    def title
      @first.strftime("%B %Y")
    end

    # The month's days as rows of seven cells, padded with nil-dated cells
    # before the first and after the last so every row runs Monday through
    # Sunday.
    #: () -> Array[Array[Cell]]
    def weeks
      last = Date.new(@first.year, @first.month, -1)
      days = Array.new((@first.wday - 1) % 7) + (@first..last).to_a
      days.fill(nil, days.length, -days.length % 7)
      days.each_slice(7).map { |week| week_cells(week) }
    end

    private

    # Multi-day events render as spanning bars; earlier-starting (then longer)
    # bars claim lower lanes so the stacking is stable across the weeks.
    #: () -> Array[GoogleCalendar::EventView]
    def multi_day
      @multi_day ||=
        @events
          .select { |event| event.end_date > event.date }
          .sort_by { |event| [event.date, event.date - event.end_date] }
    end

    #: () -> Hash[Date, Array[GoogleCalendar::EventView]]
    def single_day_by_date
      @single_day_by_date ||= (@events - multi_day).group_by(&:date)
    end

    #: (Array[Date?] week) -> Array[Cell]
    def week_cells(week)
      dates = week.compact
      from = dates.first
      to = dates.last

      # Give each bar overlapping this week the lowest lane that's free from
      # its first visible day on.
      lanes = [] #: Array[Date] — each lane's occupied-until date
      assigned =
        multi_day.filter_map do |event|
          next if event.date > to || event.end_date < from

          start = [event.date, from].max
          lane = (0...lanes.length).find { |index| lanes[index] < start } || lanes.length
          lanes[lane] = [event.end_date, to].min
          [event, lane, start]
        end

      week.map do |date|
        next Cell.new(date: nil, spans: [], events: []) if date.nil?

        spans = [] # index assignment fills skipped lower lanes with nil
        assigned.each do |event, lane, start|
          next unless event.date <= date && date <= event.end_date

          run_end = [event.end_date, to].min
          label = date == start
          spans[lane] =
            Span.new(
              event: event,
              label: label,
              continues_left: event.date < date,
              # Run-level for the label (it stretches over the whole run);
              # day-level for the continuation segments underneath.
              continues_right: event.end_date > (label ? run_end : date),
              days: label ? (run_end - date).to_i + 1 : nil
            )
        end

        Cell.new(date: date, today: date == @today, spans: spans, events: single_day_by_date[date] || [])
      end
    end
  end
end
