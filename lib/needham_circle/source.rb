# frozen_string_literal: true

module NeedhamCircle
  # An event source.
  class Source
    attr_reader :slug, :label #: String
    attr_reader :value #: String?

    def initialize(slug, label, value)
      @slug = slug
      @label = label
      @value = value
      freeze
    end

    ALL = [
      NIL = Source.new("community", "Community Submissions", nil),
      GN = Source.new("green-needham", "Green Needham", "green-needham"),
      LWV = Source.new("lwv", "League of Women Voters", "lwv-needham"),
      LBN = Source.new("lets-bike", "Let's Bike Needham", "lets-bike-needham"),
      NCS = Source.new("concert-society", "Needham Concert Society", "needham-concert-society"),
      NF = Source.new("needham-farm", "Needham Farm", "needham-farm"),
      NH = Source.new("history", "Needham History Center", "needham-history"),
      NO = Source.new("observer", "Needham Observer", "needham-observer"),
      NPSA = Source.new("schools-arts", "NPS Fine & Performing Arts", "needham-schools-arts"),
      RC = Source.new("rotary", "Rotary Club", "needham-rotary"),
      TN = Source.new("town", "Town of Needham", "needham-gov"),
      VF = Source.new("volante-farms", "Volante Farms", "volante-farms")
    ].freeze
  end
end
