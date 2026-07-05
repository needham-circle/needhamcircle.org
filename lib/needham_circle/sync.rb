# frozen_string_literal: true

require "cgi/escape"

module NeedhamCircle
  module Sync
    # The registered syncer classes — the single source of truth for which
    # sources sync. Each fetcher class calls `Sync.register(self)` in its body,
    # so this list is derived from the classes themselves rather than a parallel
    # names array, and there is no name->class lookup to keep in step. A source's
    # feed name (its `sync:<name>` rake task, CI matrix entry, and bin/console
    # helper) is just its class name in snake_case; see .name_for.
    @fetchers = []

    #: (Class fetcher) -> void
    def self.register(fetcher)
      @fetchers << fetcher
    end

    #: () -> Array[Class]
    def self.fetchers
      @fetchers
    end

    # A fetcher's feed name, e.g. NeedhamGov -> "needham_gov". Names are always
    # derived from the class this way, never parsed back into one.
    #: (Class fetcher) -> String
    def self.name_for(fetcher)
      fetcher.name.split("::").last.gsub(/([a-z])([A-Z])/, '\1_\2').downcase
    end

    # The feed names, sorted, for the rake tasks and CI matrix.
    #: () -> Array[String]
    def self.source_names
      fetchers.map { |fetcher| name_for(fetcher) }.sort
    end

    # Normalized shape produced by every source-specific syncer. Times are
    # strings in "YYYY-MM-DDTHH:MM:SS" form, paired with an IANA timezone, so
    # Google Calendar receives wall-clock times in the source's zone rather
    # than having us round-trip through Ruby Time and risk a TZ shift.
    Event =
      Struct.new(
        :source_id,
        :title,
        :description,
        :location,
        :url,
        :start_at,
        :end_at,
        :timezone,
        keyword_init: true
      )

    # Identifiable User-Agent for all outbound fetches. Ruby's default
    # "User-Agent: Ruby" is opaque and CivicPlus 404s it.
    USER_AGENT = "NeedhamCircleSync/1.0 (+https://github.com/kddnewton/needham-circle)"

    # Reduces a source's HTML description to plain text for display. Drops
    # <script>/<style> blocks (contents and all, so CSS/JS never leaks into the
    # text), turns <br> and block-level boundaries into newlines so paragraph
    # structure survives, strips remaining tags to spaces, decodes HTML
    # entities, and collapses horizontal whitespace (including &nbsp;). The
    # output is meant to render with `white-space: pre-line`.
    #: (String? html) -> String
    def self.html_to_text(html)
      return "" if html.nil? || html.empty?

      text =
        html
          .gsub(%r{<(script|style)\b[^>]*>.*?</\1>}mi, " ")
          .gsub(%r{<br\s*/?>}i, "\n")
          .gsub(%r{</(p|div|li|ul|ol|h[1-6]|blockquote|tr)>}i, "\n")
          .gsub(/<[^>]+>/, " ")

      CGI.unescapeHTML(text)
        .gsub(/&nbsp;/i, " ")
        .gsub(/[^\S\n]+/, " ") # collapse horizontal whitespace, keep newlines
        .gsub(/ *\n\s*/, "\n") # collapse newline runs (and stray space) to one
        .strip
    end
  end
end
