# frozen_string_literal: true

require "test_helper"

module NeedhamCircle
  class AppTest < Minitest::Test
    include Rack::Test::Methods

    class FakeCalendar
      attr_accessor :events_to_return, :list_error, :create_error
      attr_reader :created, :last_query

      def initialize
        @events_to_return = []
        @list_error = nil
        @create_error = nil
        @created = []
        @last_query = nil
      end

      def list_events(_calendar_id, query: nil)
        @last_query = query
        GoogleCalendar::Result.new(
          @list_error ? nil : @events_to_return,
          @list_error
        )
      end

      def create_event(calendar_id, event_form)
        @created << [calendar_id, event_form]
        GoogleCalendar::Result.new(
          @create_error ? nil : true,
          @create_error
        )
      end
    end

    class FakeMailer
      attr_accessor :deliver_error
      attr_reader :delivered

      def initialize
        @deliver_error = nil
        @delivered = []
      end

      def deliver_contact(form)
        @delivered << form
        Mailer::Result.new(@deliver_error)
      end
    end

    # Each test gets a unique synthetic IP. The RateLimit middleware lives on the
    # shared App and persists @hits across tests; without distinct
    # IPs, the test order would determine whether limits trip.
    @@ip_counter = 0

    def app
      App
    end

    def setup
      @@ip_counter += 1
      @test_ip = "10.99.#{@@ip_counter / 256 % 256}.#{@@ip_counter % 256}"
      @fake_calendar = FakeCalendar.new
      Thread.current[:google_calendar] = @fake_calendar
      @fake_mailer = FakeMailer.new
      Thread.current[:mailer] = @fake_mailer
    end

    def teardown
      Thread.current[:google_calendar] = nil
      Thread.current[:mailer] = nil
    end

    def get(path, params = {}, rack_env = {})
      super(path, params, rack_env.merge("REMOTE_ADDR" => @test_ip))
    end

    def post(path, params = {}, rack_env = {})
      super(path, params, rack_env.merge("REMOTE_ADDR" => @test_ip))
    end

    def test_home_page_renders_welcome_and_linked_boxes
      get "/"
      assert_equal 200, last_response.status
      assert_includes last_response.body, "Welcome to Needham Circle"
      # The landing page uses the wide content card.
      assert_includes last_response.body, %(<body class="wide">)
      # The three content boxes link to the sections they describe.
      assert_match(%r{href="/events"[^>]*>View Events}, last_response.body)
      assert_match(%r{href="/submit"[^>]*>Submit an Event}, last_response.body)
      assert_match(%r{href="/contact"[^>]*>Contact Us}, last_response.body)
    end

    def test_about_page_renders
      get "/about"
      assert_equal 200, last_response.status
      assert_includes last_response.body, "About Needham Circle"
    end

    def test_index_renders_events_from_calendar
      get "/events"
      assert_equal 200, last_response.status
    end

    def test_index_defaults_to_list_view_with_calendar_toggle_link
      @fake_calendar.events_to_return = [event_view(summary: "Town Meeting")]
      get "/events"
      assert_equal 200, last_response.status
      # The list markup renders and the toggle marks List active.
      assert_includes events_region, %(<ul class="events">)
      refute_includes events_region, %(<table class="cal-month">)
      assert_match(/data-view="list"[^>]*aria-current="true"/, last_response.body)
      assert_match(%r{href="/events\?view=calendar"[^>]*data-view="calendar"}, last_response.body)
      # The list view keeps the standard-width layout.
      refute_includes last_response.body, %(<body class="wide">)
    end

    def test_index_renders_calendar_view_when_requested
      @fake_calendar.events_to_return = [
        event_view(summary: "Town Meeting"),
        # An event on today itself, so today's month grid (and the cal-today
        # cell) renders even when tomorrow falls in the next month.
        event_view(summary: "Coffee Hour", start: Time.now)
      ]
      get "/events", { "view" => "calendar" }
      assert_equal 200, last_response.status
      assert_includes events_region, %(<table class="cal-month">)
      assert_includes events_region, "Town Meeting"
      refute_includes events_region, %(<ul class="events">)
      assert_match(/data-view="calendar"[^>]*aria-current="true"/, last_response.body)
      # The event lands on tomorrow's grid, and today's cell is highlighted.
      tomorrow = (Time.now + 86_400).strftime("%B %Y")
      assert_includes last_response.body, "#{tomorrow}</caption>"
      assert_includes last_response.body, %(class="cal-day cal-today")
      # The month grid gets the wide layout.
      assert_includes last_response.body, %(<body class="wide">)
    end

    def test_calendar_view_is_preserved_in_filter_urls
      get "/events", { "view" => "calendar", "source" => "lwv" }
      assert_equal 200, last_response.status
      # Source toggle links and the search form keep the calendar view.
      assert_match(/href="[^"]*view=calendar[^"]*"[^>]*data-source="lwv"/, last_response.body)
      assert_includes last_response.body, %(<input type="hidden" name="view" value="calendar">)
      # The list toggle link drops the param but keeps the source.
      assert_match(%r{href="/events\?source=lwv"[^>]*data-view="list"}, last_response.body)
    end

    def test_events_fragment_renders_calendar_for_fetch_requests
      @fake_calendar.events_to_return = [event_view(summary: "Town Meeting")]
      get "/events", { "view" => "calendar" }, { "HTTP_X_REQUESTED_WITH" => "fetch" }
      assert_equal 200, last_response.status
      assert_includes last_response.body, %(<table class="cal-month">)
      # The fragment has no page chrome around it.
      refute_includes last_response.body, "<html"
      refute_includes last_response.body, "data-filters"
    end

    def test_calendar_view_shows_times_source_colors_and_overflow
      base = Time.now + 86_400
      @fake_calendar.events_to_return = Array.new(6) { |i| event_view(summary: "Meeting #{i}", start: base) }
      get "/events", { "view" => "calendar" }
      assert_equal 200, last_response.status
      # Each visible event carries its source color and a compact time; fake
      # events have no source, so they take the community navy.
      assert_includes events_region, "--event-color: #1c478e"
      assert_includes events_region, %(<span class="cal-event-time">)
      # Six same-day events collapse to three plus a "+3 more" list link.
      assert_equal 3, events_region.scan("cal-event-time").length
      assert_match(%r{<p class="cal-more"><a href="/events">\+3 more</a></p>}, events_region)
    end

    def test_calendar_view_spans_multi_day_events
      from = Date.today + 7
      @fake_calendar.events_to_return = [all_day_event_view(summary: "Art Festival", from: from, days: 3)]
      get "/events", { "view" => "calendar" }
      assert_equal 200, last_response.status
      assert_includes events_region, "Art Festival"
      # One bar segment per covered day, joined across the cells.
      assert_equal 3, events_region.scan(%(<p class="cal-span)).length
    end

    def test_calendar_view_renders_friendly_error_on_calendar_failure
      @fake_calendar.list_error = Google::Apis::ServerError.new("boom")
      get "/events", { "view" => "calendar" }
      assert_equal 200, last_response.status
      assert_includes last_response.body, "trouble loading events"
    end

    def test_index_renders_friendly_error_on_calendar_failure
      @fake_calendar.list_error = Google::Apis::ServerError.new("boom")
      get "/events"
      assert_equal 200, last_response.status
      assert_includes last_response.body, "trouble loading events"
    end

    def test_index_renders_source_filter_with_nothing_selected
      get "/events"
      assert_equal 200, last_response.status
      # Every source is an option in the dropdown.
      assert_includes last_response.body, "League of Women Voters"
      assert_includes last_response.body, "Needham Observer"
      # With no selection, the count badge and applied-chips row are hidden.
      assert_includes last_response.body, "data-source-count hidden"
      assert_includes last_response.body, "data-applied hidden"
    end

    def test_index_marks_selected_source_and_shows_applied_chip
      get "/events", { "source" => "lwv" }
      assert_equal 200, last_response.status
      # The matching dropdown option is checked.
      assert_match(/data-source="lwv"[^>]*aria-checked="true"/, last_response.body)
      # The applied-chips row is shown (not hidden) with a removable chip.
      assert_includes last_response.body, "data-applied>"
      assert_includes last_response.body, "Remove League of Women Voters filter"
      refute_includes last_response.body, "data-source-count hidden"
    end

    def test_resources_page_renders_sections_and_entries
      get "/resources"
      assert_equal 200, last_response.status
      assert_includes last_response.body, "Town Offices &amp; Resources"
      assert_includes last_response.body, "Needham Public Library"
      assert_includes last_response.body, "Parks &amp; Public Spaces"
      assert_includes last_response.body, %(<span class="contact-label">Phone</span>)
      assert_includes last_response.body, %(<span class="contact-label">Website</span>)
      assert_includes last_response.body, %(<span class="contact-label">Map</span>)
    end

    def test_submit_page_renders_form_with_csrf_token
      get "/submit"
      assert_equal 200, last_response.status
      assert_includes last_response.body, "Submit an Event"
      assert_match(/name="authenticity_token" value="[^"]+"/, last_response.body)
    end

    def test_post_without_csrf_token_is_rejected
      post "/submit", "title" => "Hi"
      assert_equal 403, last_response.status
      assert_empty @fake_calendar.created
    end

    def test_valid_submission_creates_event_and_renders_thanks
      submit(
        "title" => "Town Meeting",
        "host" => "Town of Needham",
        "description" => "Discuss things",
        "location" => "Town Hall",
        "start_time" => future_local(1),
        "end_time" => future_local(3),
        "email" => "organizer@example.com"
      )

      assert_equal 200, last_response.status
      assert_includes last_response.body, "Thanks!"
      assert_equal 1, @fake_calendar.created.size
      calendar_id, form = @fake_calendar.created.first
      assert_equal "submissions-cal-id", calendar_id
      assert_equal "Town Meeting", form.coerced_for(:title)
      assert_equal "Town of Needham", form.coerced_for(:host)
      assert_equal "organizer@example.com", form.coerced_for(:email)
    end

    def test_submission_requires_a_host
      submit(
        "title" => "No Host",
        "start_time" => future_local(1),
        "end_time" => future_local(3),
        "email" => "organizer@example.com"
      )

      assert_includes last_response.body, "Name of host organization/business is required."
      assert_empty @fake_calendar.created
    end

    def test_submission_requires_a_valid_email
      submit(
        "title" => "No Email",
        "start_time" => future_local(1),
        "end_time" => future_local(3),
        "email" => "not-an-email"
      )

      assert_includes last_response.body, "Email must be a valid email address."
      assert_empty @fake_calendar.created
    end

    def test_invalid_submission_shows_field_errors_and_does_not_create
      submit(
        "title" => "",
        "start_time" => "garbage",
        "end_time" => ""
      )

      assert_includes last_response.body, "Title is required."
      assert_includes last_response.body, "Start time is required to be a valid time."
      assert_empty @fake_calendar.created
    end

    def test_end_before_start_is_rejected
      submit(
        "title" => "Inverted",
        "start_time" => future_local(3),
        "end_time" => future_local(1)
      )

      assert_includes last_response.body, "End time must be after start time."
      assert_empty @fake_calendar.created
    end

    def test_past_start_time_is_rejected
      submit(
        "title" => "Yesterday",
        "start_time" => (Time.now - 3600).strftime("%Y-%m-%dT%H:%M"),
        "end_time" => future_local(1)
      )

      assert_includes last_response.body, "Start time must be in the future."
      assert_empty @fake_calendar.created
    end

    def test_xss_payload_in_form_is_escaped_on_rerender
      submit(
        "title" => '"><script>alert(1)</script>',
        "start_time" => "",
        "end_time" => ""
      )

      refute_includes last_response.body, "<script>alert(1)"
      assert_includes last_response.body, "&lt;script&gt;"
    end

    def test_calendar_create_failure_shows_generic_error
      @fake_calendar.create_error = Google::Apis::ServerError.new("nope")
      submit(
        "title" => "Picnic",
        "start_time" => future_local(1),
        "end_time" => future_local(3)
      )

      refute_includes last_response.body, "Thanks!"
      assert_includes last_response.body, "problem with your submission"
    end

    def test_rate_limit_kicks_in_after_five_posts
      @test_ip = "192.168.99.99"
      5.times do |i|
        submit("title" => "ok #{i}", "start_time" => "", "end_time" => "")
        refute_equal 429, last_response.status, "request #{i + 1} should not be rate limited"
      end

      submit("title" => "ok 6", "start_time" => "", "end_time" => "")
      assert_equal 429, last_response.status
    end

    def test_contact_page_renders_form_with_csrf_token
      get "/contact"
      assert_equal 200, last_response.status
      assert_includes last_response.body, "Contact"
      assert_match(/name="authenticity_token" value="[^"]+"/, last_response.body)
    end

    def test_contact_post_without_csrf_token_is_rejected
      post "/contact", "name" => "Jane"
      assert_equal 403, last_response.status
      assert_empty @fake_mailer.delivered
    end

    def test_valid_contact_delivers_message_and_renders_thanks
      contact(
        "name" => "Jane Doe",
        "email" => "jane@example.com",
        "subject" => "Hello",
        "message" => "I would like to help out."
      )

      assert_equal 200, last_response.status
      assert_includes last_response.body, "Thanks for reaching out!"
      assert_equal 1, @fake_mailer.delivered.size
      form = @fake_mailer.delivered.first
      assert_equal "Jane Doe", form.coerced_for(:name)
      assert_equal "jane@example.com", form.coerced_for(:email)
      assert_equal "I would like to help out.", form.coerced_for(:message)
    end

    def test_contact_requires_name_email_and_message
      contact("name" => "", "email" => "", "message" => "")

      assert_includes last_response.body, "Name is required."
      assert_includes last_response.body, "Email is required."
      assert_includes last_response.body, "Message is required."
      assert_empty @fake_mailer.delivered
    end

    def test_contact_requires_a_valid_email
      contact("name" => "Jane", "email" => "not-an-email", "message" => "Hi")

      assert_includes last_response.body, "Email must be a valid email address."
      assert_empty @fake_mailer.delivered
    end

    def test_contact_delivery_failure_shows_generic_error
      @fake_mailer.deliver_error = Net::SMTPServerBusy.new("busy")
      contact("name" => "Jane", "email" => "jane@example.com", "message" => "Hi")

      refute_includes last_response.body, "Thanks for reaching out!"
      assert_includes last_response.body, "problem sending your message"
    end

    def test_contact_rate_limit_kicks_in_after_five_posts
      @test_ip = "192.168.77.77"
      5.times do |i|
        contact("name" => "", "email" => "", "message" => "")
        refute_equal 429, last_response.status, "request #{i + 1} should not be rate limited"
      end

      contact("name" => "", "email" => "", "message" => "")
      assert_equal 429, last_response.status
    end

    private

    def submit(params)
      get "/submit"
      match = last_response.body.match(/name="authenticity_token" value="([^"]+)"/)
      flunk "no CSRF token in /submit response (status=#{last_response.status})" unless match
      post "/submit", params.merge("authenticity_token" => match[1])
    end

    def contact(params)
      get "/contact"
      match = last_response.body.match(/name="authenticity_token" value="([^"]+)"/)
      flunk "no CSRF token in /contact response (status=#{last_response.status})" unless match
      post "/contact", params.merge("authenticity_token" => match[1])
    end

    def future_local(hours_ahead)
      (Time.now + hours_ahead * 3600).strftime("%Y-%m-%dT%H:%M")
    end

    # The rendered events region, without the rest of the page — the skeleton
    # templates further down legitimately contain both views' markup.
    def events_region
      last_response.body.split("<div data-events>").last.split("<template").first
    end

    def event_view(summary:, location: nil, description: nil, email: nil, start: Time.now + 86_400)
      google_event =
        Google::Apis::CalendarV3::Event.new(
          summary: summary,
          location: location,
          description: description,
          start: Google::Apis::CalendarV3::EventDateTime.new(date_time: start),
          end: Google::Apis::CalendarV3::EventDateTime.new(date_time: start + 3600)
        )

      if email
        google_event.extended_properties =
          Google::Apis::CalendarV3::Event::ExtendedProperties.new(
            private: { "email" => email }
          )
      end

      GoogleCalendar::EventView.for(google_event)
    end

    def all_day_event_view(summary:, from:, days:)
      google_event =
        Google::Apis::CalendarV3::Event.new(
          summary: summary,
          start: Google::Apis::CalendarV3::EventDateTime.new(date: from),
          # Google all-day end dates are exclusive.
          end: Google::Apis::CalendarV3::EventDateTime.new(date: from + days)
        )

      GoogleCalendar::EventView.for(google_event)
    end
  end
end
