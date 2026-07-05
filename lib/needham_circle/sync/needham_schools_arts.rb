# frozen_string_literal: true

require "json"

module NeedhamCircle
  module Sync
    # Needham Public Schools runs the SharpSchool CMS. Its Fine & Performing Arts
    # calendar is a React portlet backed by an undocumented ASMX endpoint, so we
    # POST the same "Modern_Events" query the portlet issues, scoped to this
    # calendar and a forward date window.
    #
    # The site's iCal handler is Cloudflare-blocked, but this /Common/... API
    # path is reachable; the portlet/calendar ids come from the page's
    # data-portlet-instance-id / data-calendar-id. Expect brittleness if the
    # district changes CMS or those ids.
    class NeedhamSchoolsArts
      Sync.register(self)

      EVENTS_URL =
        "https://www.needham.k12.ma.us/Common/controls/WorkspaceCalendar/ws/WorkspaceCalendarWS.asmx/Modern_Events"
      PORTLET_INSTANCE_ID = 162929
      CALENDAR_ID = 3723868
      WINDOW_DAYS = 400 # how far ahead to request events

      # The portlet reports wall-clock times in Needham's zone; we pass the
      # components straight through and let Google apply DST.
      TIMEZONE = "America/New_York"

      #: (?fetch: ^() -> Hash[String, untyped]?, ?logger: Logger?) -> void
      def initialize(fetch: nil, logger: nil)
        @fetch = fetch || method(:fetch_from_api)
        @logger = logger
      end

      #: () -> Source
      def source
        Source::NPSA
      end

      #: () -> Array[Event]?
      def fetch_events
        payload = @fetch.call
        return nil if payload.nil?

        events = payload.dig("d", "events") || []
        events.filter_map { |raw| build_event(raw) }
      end

      private

      #: () -> Hash[String, untyped]?
      def fetch_from_api
        from = Time.now
        body =
          JSON.generate(
            "portletInstanceId" => PORTLET_INSTANCE_ID,
            "primaryCalendarId" => CALENDAR_ID,
            "calendarIds" => [CALENDAR_ID],
            "localFromDate" => from.strftime("%Y-%m-%d"),
            "localToDate" => (from + WINDOW_DAYS * 86_400).strftime("%Y-%m-%d"),
            "filterFieldValue" => "",
            "searchText" => "",
            "categoryFieldValue" => "",
            "filterOptions" => nil
          )
        Sync::HTTP.post_json(EVENTS_URL, body, logger: @logger)
      end

      #: (Hash[String, untyped] raw) -> Event?
      def build_event(raw)
        start_at = format_time(raw["localStartDate"])
        return nil if start_at.nil? # no usable start — can't place it on a calendar

        Event.new(
          source_id: raw["eventID"].to_s,
          title: raw["name"].to_s,
          description: Sync.html_to_text(raw["description"]),
          location: raw["location"].to_s,
          url: "",
          start_at: start_at,
          end_at: format_time(raw["localEndDate"]),
          timezone: TIMEZONE
        )
      end

      # "2026-09-19 19:30:00" -> "2026-09-19T19:30:00" (Google wants the "T").
      #: (String? string) -> String?
      def format_time(string)
        return nil if string.nil? || string.empty?
        string.sub(" ", "T")
      end
    end
  end
end
