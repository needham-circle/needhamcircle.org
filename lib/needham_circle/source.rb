# frozen_string_literal: true

module NeedhamCircle
  # An event source.
  class Source
    attr_reader :slug, :label, :color #: String
    attr_reader :value #: String?

    def initialize(slug, label, value, color)
      @slug = slug
      @label = label
      @value = value
      @color = color
      freeze
    end

    # Each source's identifying color, used by the calendar view's bars and
    # dots (with the event title always alongside — color never carries the
    # identity alone) and the filter dropdown's swatches. The set is a muted
    # "heritage" register harmonized with the site navy: all twelve keep
    # white text at >= 4.5:1 contrast and were validated together for
    # color-vision-deficiency separation (worst adjacent deutan ΔE 12.4).
    ALL = [
      NIL = Source.new("community", "Community Submissions", nil, "#1c478e"),
      GN = Source.new("green-needham", "Green Needham", "green-needham", "#187a4e"),
      LWV = Source.new("lwv", "League of Women Voters", "lwv-needham", "#2b689e"),
      LBN = Source.new("lets-bike", "Let's Bike Needham", "lets-bike-needham", "#8f3d5e"),
      NCS = Source.new("concert-society", "Needham Concert Society", "needham-concert-society", "#52489f"),
      NF = Source.new("needham-farm", "Needham Farm", "needham-farm", "#74491e"),
      NH = Source.new("history", "Needham History Center", "needham-history", "#9e3b3b"),
      NO = Source.new("observer", "Needham Observer", "needham-observer", "#047d80"),
      NPSA = Source.new("schools-arts", "NPS Fine & Performing Arts", "needham-schools-arts", "#6d2d7d"),
      RC = Source.new("rotary", "Rotary Club", "needham-rotary", "#92610e"),
      TN = Source.new("town", "Town of Needham", "needham-gov", "#9c4a1f"),
      VF = Source.new("volante-farms", "Volante Farms", "volante-farms", "#5e7014")
    ].freeze

    # The source an event's stored value maps back to; events without one
    # (or with an unrecognized one) are community submissions.
    #: (String? value) -> Source
    def self.for_value(value)
      ALL.find { |source| source.value == value } || NIL
    end
  end
end
