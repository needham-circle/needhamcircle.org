# frozen_string_literal: true

module NeedhamCircle
  module Sync
    # Volante Farms lists events through the "Calee" Shopify calendar app
    # (theweeapps.com), whose storefront widget form-POSTs to the vendor's
    # api.php for the store's full event list. We issue the same request and
    # keep only the Summer Concert series — the rest of the calendar is
    # tastings, workshops, sales, and store hours.
    class VolanteFarms
      Sync.register(self)

      ENDPOINT = "https://theweeapps.com/caly-v2/api.php"
      SHOP = "volante-farms.myshopify.com"

      # Concert events carry no per-event URL, so link to the calendar page.
      PAGE_URL = "https://shop.volantefarms.com/pages/events-1"

      # Matches both title shapes the farm has used: "Summer Concert #2 -
      # <act>" and "Free Summer Concert Series: <act>".
      SERIES = /summer concert/i

      # The feed reports wall-clock times in the farm's zone (its per-event
      # iana_timezone is always America/New_York); we pass the components
      # straight through and let Google apply DST.
      TIMEZONE = "America/New_York"

      # The feed includes every past event, previous concert seasons included,
      # so we drop ones already over. Its times are Eastern wall clock; rather
      # than pull in tzinfo to render `now` in that zone, we compare against
      # UTC wall clock minus a day. Eastern trails UTC by 4-5 hours, so the
      # cutoff is always safely in the past locally — keeping a just-ended
      # concert a few hours longer is harmless (the sync only upserts).
      PAST_GRACE = 24 * 60 * 60

      #: (?fetch: ^() -> Hash[String, untyped]?, ?now: Time?, ?logger: Logger?) -> void
      def initialize(fetch: nil, now: nil, logger: nil)
        @fetch = fetch || method(:fetch_from_api)
        @now = now
        @logger = logger
      end

      #: () -> Source
      def source
        Source::VF
      end

      #: () -> Array[Event]?
      def fetch_events
        payload = @fetch.call
        return nil if payload.nil?

        # The API returns 200 with {"result" => "fail", "msg" => ...} on
        # failure, so a missing event list is an error, not an empty feed.
        events = payload["event_data"]
        if events.nil?
          log("response had no event_data (msg: #{payload["msg"].inspect})")
          return nil
        end

        # The feed keeps every past season and the farm has already retitled
        # the series between seasons (see SERIES), so zero matches anywhere in
        # the feed means the title shape drifted again. Fail so the sync turns
        # red rather than quietly syncing nothing from then on.
        concerts = events.select { |raw| SERIES.match?(raw["event_title"]) }
        if concerts.empty?
          log("none of the #{events.length} events in the feed matched #{SERIES.inspect}")
          return nil
        end

        cutoff = ((@now || Time.now).utc - PAST_GRACE).strftime("%Y-%m-%d %H:%M:%S")
        concerts.filter_map do |raw|
          next if raw["is_draft_event"].to_i != 0

          if raw["is_recurring"].to_i != 0
            # A recurring row carries only its first occurrence's times, with
            # the series end in end_recurring_event, so it can't be represented
            # as one dated event. The farm enters each concert individually
            # today; if a season ever arrives as one recurring rule instead,
            # fail the sync so it turns red rather than silently dropping the
            # season — unless the rule already ended, which is as ignorable as
            # any other past event.
            series_end = raw["end_recurring_event"]
            next if series_end && series_end < cutoff

            log("cannot represent recurring event #{raw["event_id"]}: #{raw["event_title"]}")
            return nil
          end

          next if raw["end_date_time"] < cutoff

          build_event(raw)
        end
      end

      private

      #: () -> Hash[String, untyped]?
      def fetch_from_api
        Sync::HTTP.post_form(
          ENDPOINT,
          {
            "shop" => SHOP,
            "req_calling_method" => "get_front_event_data",
            "calendar_type" => "original",
            "calendar_id" => "0"
          },
          logger: @logger
        )
      end

      #: (Hash[String, untyped] raw) -> Event
      def build_event(raw)
        Event.new(
          source_id: raw.fetch("event_id").to_s,
          title: raw["event_title"].strip,
          description: Sync.html_to_text(raw["event_details"]),
          location: raw["event_location"].to_s.strip,
          url: event_url(raw),
          start_at: Sync.format_time(raw["start_date_time"]),
          end_at: Sync.format_time(raw["end_date_time"]),
          timezone: TIMEZONE
        )
      end

      #: (Hash[String, untyped] raw) -> String
      def event_url(raw)
        url = raw["external_url"].to_s.strip
        url.empty? ? PAGE_URL : url
      end

      #: (String message) -> void
      def log(message)
        @logger&.error("Sync::VolanteFarms #{message}")
      end
    end
  end
end
