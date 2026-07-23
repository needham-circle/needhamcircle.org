# frozen_string_literal: true

module NeedhamCircle
  class GoogleCalendar
    # One page of upcoming events; the /events views render everything
    # returned, and the calendar view drops its trailing month when this cap
    # was hit (see MonthGrid.build's truncated flag).
    MAX_RESULTS = 250

    class Result
      attr_reader :value #: T
      attr_reader :error #: Google::Apis::Error?

      #: (T? value, Google::Apis::Error? error) -> void
      def initialize(value, error)
        @value = value
        @error = error
      end

      #: () { () -> T } -> Result[T]
      def self.wrap
        value = yield
        new(value, nil)
      rescue Google::Apis::Error => error
        new(nil, error)
      end
    end

    class EventView
      # Pairs the event with the formatter matching its start kind: Google
      # sends date_time for timed events and date for all-day ones.
      #: (Google::Apis::CalendarV3::Event event) -> EventView
      def self.for(event)
        formatter =
          if event.start.date_time
            EventDateTimeFormatter.new
          elsif event.start.date
            EventDateFormatter.new
          else
            raise
          end

        new(event, formatter)
      end

      #: (Google::Apis::CalendarV3::Event event, (EventDateTimeFormatter | EventDateFormatter) formatter) -> void
      def initialize(event, formatter)
        @event = event
        @formatter = formatter
      end

      #: () -> String
      def title
        @event.summary
      end

      #: () -> String?
      def location
        @event.location
      end

      #: () -> String?
      def description
        @event.description
      end

      #: () -> String?
      def source
        @event.extended_properties&.private&.[]("source")
      end

      #: () -> String?
      def url
        if (candidate = @event.source&.url)&.match?(%r{\Ahttps?://})
          candidate
        end
      end

      # Memoized — the grid layout consults these dates for every cell.
      #: () -> Date
      def date
        @date ||= @formatter.date(@event)
      end

      # The last day the event occupies, for laying multi-day events across
      # the calendar grid. Never before #date. Memoized like #date.
      #: () -> Date
      def end_date
        @end_date ||= @formatter.end_date(@event)
      end

      #: () -> String
      def iso8601
        @formatter.iso8601(@event)
      end

      #: () -> String
      def formatted_starts_at
        @formatter.formatted_starts_at(@event)
      end

      # The compact start time shown in the calendar's day cells ("7pm",
      # "7:30pm"); all-day events have none.
      #: () -> String?
      def formatted_time
        @formatter.formatted_time(@event)
      end

      #: () -> String?
      def formatted_ends_at
        @formatter.formatted_ends_at(@event)
      end

      #: () -> String
      def formatted_month
        @formatter.formatted_month(@event)
      end
    end

    class EventDateTimeFormatter
      LONG_FORMAT = "%A, %B %-d at %-l:%M %p"

      #: (Google::Apis::CalendarV3::Event event) -> Date
      def date(event)
        event.start.date_time.to_date
      end

      #: (Google::Apis::CalendarV3::Event event) -> Date
      def end_date(event)
        ends = event.end.date_time
        ending = ends.to_date
        # An event ending exactly at midnight doesn't occupy that day.
        ending -= 1 if ends.hour.zero? && ends.min.zero?
        [ending, date(event)].max
      end

      #: (Google::Apis::CalendarV3::Event event) -> String
      def iso8601(event)
        event.start.date_time.iso8601
      end

      #: (Google::Apis::CalendarV3::Event event) -> String
      def formatted_starts_at(event)
        event.start.date_time.strftime(LONG_FORMAT)
      end

      #: (Google::Apis::CalendarV3::Event event) -> String
      def formatted_time(event)
        starts = event.start.date_time
        starts.strftime(starts.min.zero? ? "%-l%P" : "%-l:%M%P")
      end

      #: (Google::Apis::CalendarV3::Event event) -> String
      def formatted_ends_at(event)
        ends = event.end.date_time

        if ends.to_date == event.start.date_time.to_date
          ends.strftime("%-l:%M %p")
        else
          ends.strftime(LONG_FORMAT)
        end
      end

      #: (Google::Apis::CalendarV3::Event event) -> String
      def formatted_month(event)
        event.start.date_time.strftime("%B %Y")
      end
    end

    class EventDateFormatter
      LONG_FORMAT = "%A, %B %-d"

      #: (Google::Apis::CalendarV3::Event event) -> Date
      def date(event)
        event.start.date
      end

      # Google Calendar all-day end dates are exclusive, so the inclusive
      # last day is the day before (clamped for zero-length events).
      #: (Google::Apis::CalendarV3::Event event) -> Date
      def end_date(event)
        [event.end.date - 1, date(event)].max
      end

      #: (Google::Apis::CalendarV3::Event event) -> String
      def iso8601(event)
        event.start.date.iso8601
      end

      #: (Google::Apis::CalendarV3::Event event) -> String
      def formatted_starts_at(event)
        event.start.date.strftime(LONG_FORMAT)
      end

      #: (Google::Apis::CalendarV3::Event event) -> String?
      def formatted_time(_event)
        nil
      end

      # A single-day event has no end to show.
      #: (Google::Apis::CalendarV3::Event event) -> String?
      def formatted_ends_at(event)
        inclusive_end = end_date(event)
        return if inclusive_end <= date(event)

        inclusive_end.strftime(LONG_FORMAT)
      end

      #: (Google::Apis::CalendarV3::Event event) -> String
      def formatted_month(event)
        event.start.date.strftime("%B %Y")
      end
    end

    #: (String key) -> void
    def initialize(key)
      @service = Google::Apis::CalendarV3::CalendarService.new
      @service.authorization =
        Google::Auth::ServiceAccountCredentials.make_creds(
          json_key_io: StringIO.new(Base64.decode64(key)),
          scope: ["https://www.googleapis.com/auth/calendar.events"]
        )
    end

    #: (String calendar_id, ?query: String?) -> Result[Array[EventView]]
    def list_events(calendar_id, query: nil)
      Result.wrap do
        @service
          .list_events(
            calendar_id,
            q: query,
            single_events: true,
            order_by: "startTime",
            time_min: Time.now.iso8601,
            max_results: MAX_RESULTS
          )
          .items
          .map { |google_event| EventView.for(google_event) }
      end
    end

    #: (String calendar_id, EventForm event_form) -> Result[void]
    def create_event(calendar_id, event_form)
      Result.wrap do
        google_event =
          Google::Apis::CalendarV3::Event.new(
            summary: event_form.coerced_for(:title),
            description: event_form.coerced_for(:description),
            location: event_form.coerced_for(:location),
            start: event_date_time(event_form.coerced_for(:start_time)),
            end: event_date_time(event_form.coerced_for(:end_time)),
            # The submitter's contact email and host organization are
            # moderator-only metadata, kept in private extended properties so
            # they never surface in the description the public events list now
            # renders.
            extended_properties:
              Google::Apis::CalendarV3::Event::ExtendedProperties.new(
                private: {
                  "email" => event_form.coerced_for(:email),
                  "host" => event_form.coerced_for(:host)
                }
              )
          )

        # Google rejects Event::Source with a blank url. Only attach the source
        # block when we actually have one to link to.
        if (url = event_form.coerced_for(:url)) && !url.empty?
          google_event.source =
            Google::Apis::CalendarV3::Event::Source.new(
              title: "Event website",
              url: url
            )
        end

        @service.insert_event(calendar_id, google_event)
      end
    end

    #: (String calendar_id, String source) -> Result[Hash[String, String]]
    def source_ids(calendar_id, source)
      Result.wrap do
        @service
          .list_events(
            calendar_id,
            private_extended_property: ["source=#{source}"],
            single_events: true,
            show_deleted: false,
            max_results: 2500
          )
          .items
          .each_with_object({}) do |google_event, ids|
            source_id = google_event.extended_properties&.private&.[]("source_id")
            ids[source_id] = google_event.id if source_id
          end
      end
    end

    #: (String calendar_id, String source, String? existing_event_id, Sync::Event event) -> Result[void]
    def upsert_source_event(calendar_id, source, existing_event_id, event)
      Result.wrap do
        google_event =
          Google::Apis::CalendarV3::Event.new(
            summary: event.title,
            description: event.description,
            location: event.location,
            start: source_date_time(event.start_at, event.timezone),
            end: source_date_time(event.end_at, event.timezone),
            extended_properties:
              Google::Apis::CalendarV3::Event::ExtendedProperties.new(
                private: { "source" => source, "source_id" => event.source_id }
              )
          )

        # Google rejects Event::Source with a blank url. Only attach the source
        # block when we actually have one to link to.
        if event.url && !event.url.empty?
          google_event.source =
            Google::Apis::CalendarV3::Event::Source.new(
              title: source,
              url: event.url
            )
        end

        if existing_event_id
          @service.update_event(calendar_id, existing_event_id, google_event)
        else
          @service.insert_event(calendar_id, google_event)
        end
      end
    end

    private

    #: (Time time) -> Google::Apis::CalendarV3::EventDateTime
    def event_date_time(time)
      Google::Apis::CalendarV3::EventDateTime.new(
        date_time: time.strftime("%Y-%m-%dT%H:%M:%S"),
        time_zone: "America/New_York"
      )
    end

    #: (String iso, String timezone) -> Google::Apis::CalendarV3::EventDateTime
    def source_date_time(iso, timezone)
      Google::Apis::CalendarV3::EventDateTime.new(
        date_time: iso,
        time_zone: timezone
      )
    end
  end
end
