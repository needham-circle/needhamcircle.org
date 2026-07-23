# frozen_string_literal: true

require "test_helper"

module NeedhamCircle
  class MonthGridTest < Minitest::Test
    # Just enough of GoogleCalendar::EventView for the grid: it only reads
    # #date and #end_date (the inclusive last day).
    FakeEvent = Struct.new(:date, :end_date)

    def test_builds_one_grid_per_month_in_chronological_order
      grids =
        build(
          [
            single(Date.new(2026, 8, 6)),
            single(Date.new(2026, 7, 9)),
            single(Date.new(2026, 7, 16))
          ]
        )

      assert_equal ["July 2026", "August 2026"], grids.map(&:title)
    end

    def test_renders_gap_months_empty_instead_of_skipping_them
      grids = build([single(Date.new(2026, 7, 9)), single(Date.new(2026, 9, 12))])

      assert_equal ["July 2026", "August 2026", "September 2026"], grids.map(&:title)
      august_cells = grids[1].weeks.flatten
      assert(august_cells.all? { |cell| cell.spans.empty? && cell.events.empty? })
    end

    def test_truncated_feed_drops_the_trailing_partial_months
      # The feed was cut at the API cap somewhere in September, so September
      # (and the October tail of the multi-day event) may be missing events.
      grids =
        build(
          [
            single(Date.new(2026, 7, 9)),
            FakeEvent.new(Date.new(2026, 8, 20), Date.new(2026, 10, 2)),
            single(Date.new(2026, 9, 12))
          ],
          truncated: true
        )

      assert_equal ["July 2026", "August 2026"], grids.map(&:title)
    end

    def test_truncated_feed_keeps_the_current_month_rather_than_nothing
      grids = build([single(Date.new(2026, 7, 9)), single(Date.new(2026, 7, 16))], truncated: true)

      assert_equal ["July 2026"], grids.map(&:title)
    end

    def test_weeks_align_to_monday_with_padding
      # July 2026 starts on a Wednesday and ends on a Friday.
      weeks = build([single(Date.new(2026, 7, 9))]).first.weeks

      assert(weeks.all? { |week| week.length == 7 })
      assert_equal [nil, nil, Date.new(2026, 7, 1)], weeks.first.first(3).map(&:date)
      assert_equal [Date.new(2026, 7, 31), nil, nil], weeks.last[4, 3].map(&:date)
      assert_equal 31, weeks.flatten.map(&:date).compact.length
    end

    def test_weeks_need_no_padding_when_month_edges_align
      # February 2027 starts on a Monday and ends on a Sunday.
      weeks = build([single(Date.new(2027, 2, 14))]).first.weeks

      assert_equal 4, weeks.length
      assert_equal Date.new(2027, 2, 1), weeks.first.first.date
      assert_equal Date.new(2027, 2, 28), weeks.last.last.date
      refute_includes weeks.flatten.map(&:date), nil
    end

    def test_lists_single_day_events_on_their_day_preserving_order
      first = single(Date.new(2026, 7, 9))
      second = single(Date.new(2026, 7, 9))

      grid = build([first, second]).first
      cell = cell_for(grid, Date.new(2026, 7, 9))
      assert_equal [first, second], cell.events
      assert_empty cell.spans
    end

    def test_multi_day_event_spans_its_days_with_one_label_per_week
      # Thursday July 9 through Saturday July 11 — a single-week run.
      event = FakeEvent.new(Date.new(2026, 7, 9), Date.new(2026, 7, 11))
      grid = build([event]).first

      spans = (9..11).map { |day| cell_for(grid, Date.new(2026, 7, day)).spans[0] }
      assert_equal [true, false, false], spans.map(&:label)
      assert_equal [false, true, true], spans.map(&:continues_left)
      # The label stretches over the whole run, so its continues_right is
      # run-level: this bar ends within the week.
      assert_equal [false, true, false], spans.map(&:continues_right)
      assert_equal 3, spans[0].days
      assert_empty cell_for(grid, Date.new(2026, 7, 8)).spans
      assert_empty cell_for(grid, Date.new(2026, 7, 12)).spans
    end

    def test_multi_day_event_relabels_at_the_start_of_each_week
      # Saturday July 11 through Monday July 13 — crosses the week boundary.
      event = FakeEvent.new(Date.new(2026, 7, 11), Date.new(2026, 7, 13))
      grid = build([event]).first

      saturday = cell_for(grid, Date.new(2026, 7, 11)).spans[0]
      assert saturday.label
      assert saturday.continues_right
      assert_equal 2, saturday.days

      monday = cell_for(grid, Date.new(2026, 7, 13)).spans[0]
      assert monday.label
      assert monday.continues_left
      refute monday.continues_right
      assert_equal 1, monday.days
    end

    def test_overlapping_bars_stack_in_lanes_with_spacers
      # A (Mon-Thu) claims lane 0; B (Wed-Fri) overlaps it and takes lane 1.
      a = FakeEvent.new(Date.new(2026, 7, 6), Date.new(2026, 7, 9))
      b = FakeEvent.new(Date.new(2026, 7, 8), Date.new(2026, 7, 10))
      grid = build([b, a]).first

      wednesday = cell_for(grid, Date.new(2026, 7, 8))
      assert_equal [a, b], wednesday.spans.map(&:event)

      # Friday only carries B, held in its lane by a spacer below it.
      friday = cell_for(grid, Date.new(2026, 7, 10))
      assert_nil friday.spans[0]
      assert_equal b, friday.spans[1].event
    end

    def test_marks_the_today_cell
      grid = build([single(Date.new(2026, 7, 9))], today: Date.new(2026, 7, 9)).first

      assert cell_for(grid, Date.new(2026, 7, 9)).today
      refute cell_for(grid, Date.new(2026, 7, 10)).today
    end

    def test_ongoing_event_does_not_resurrect_past_months
      event = FakeEvent.new(Date.new(2026, 6, 1), Date.new(2026, 8, 15))
      grids = build([event], today: Date.new(2026, 7, 7))

      assert_equal ["July 2026", "August 2026"], grids.map(&:title)

      # The bar picks up mid-event at the top of the current month.
      first_cell = cell_for(grids[0], Date.new(2026, 7, 1))
      assert first_cell.spans[0].label
      assert first_cell.spans[0].continues_left
    end

    def test_multi_day_event_appears_in_every_month_it_touches
      event = FakeEvent.new(Date.new(2026, 7, 30), Date.new(2026, 8, 3))
      grids = build([event])

      assert_equal ["July 2026", "August 2026"], grids.map(&:title)

      # July's edge continues out of the grid; August's picks it back up.
      july_end = cell_for(grids[0], Date.new(2026, 7, 31)).spans[0]
      assert july_end.continues_right

      august_start = cell_for(grids[1], Date.new(2026, 8, 1)).spans[0]
      assert august_start.label
      assert august_start.continues_left
      # August 1 2026 is a Saturday, so the first run is Sat-Sun.
      assert_equal 2, august_start.days
    end

    def test_cell_shows_all_events_when_they_fit
      cell = cell_with(spans: [], events: Array.new(4) { single(Date.new(2026, 7, 9)) })

      assert_equal cell.events, cell.visible_events
      assert_equal 0, cell.overflow_count
    end

    def test_cell_collapses_overflowing_events_into_a_more_row
      cell = cell_with(spans: [], events: Array.new(6) { single(Date.new(2026, 7, 9)) })

      assert_equal cell.events.first(3), cell.visible_events
      assert_equal 3, cell.overflow_count
    end

    def test_cell_reserves_rows_for_multi_day_lanes
      lanes = [:bar, :bar]
      cell = cell_with(spans: lanes, events: Array.new(3) { single(Date.new(2026, 7, 9)) })

      assert_equal cell.events.first(1), cell.visible_events
      assert_equal 2, cell.overflow_count
    end

    private

    def cell_with(spans:, events:)
      MonthGrid::Cell.new(date: Date.new(2026, 7, 9), today: false, spans: spans, events: events)
    end

    # A fixed clock before every test event, so nothing gets clamped away.
    def build(events, today: Date.new(2026, 7, 1), truncated: false)
      MonthGrid.build(events, today: today, truncated: truncated)
    end

    def single(date)
      FakeEvent.new(date, date)
    end

    def cell_for(grid, date)
      grid.weeks.flatten.find { |cell| cell.date == date }
    end
  end
end
