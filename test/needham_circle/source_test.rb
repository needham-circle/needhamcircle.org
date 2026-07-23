# frozen_string_literal: true

require "test_helper"

module NeedhamCircle
  class SourceTest < Minitest::Test
    def test_for_value_maps_a_stored_value_to_its_source
      assert_equal Source::VF, Source.for_value("volante-farms")
      assert_equal Source::TN, Source.for_value("needham-gov")
    end

    def test_for_value_falls_back_to_community_submissions
      assert_equal Source::NIL, Source.for_value(nil)
      assert_equal Source::NIL, Source.for_value("")
      assert_equal Source::NIL, Source.for_value("unknown-feed")
    end

    def test_every_source_has_an_identifying_color
      assert(Source::ALL.all? { |source| source.color.match?(/\A#\h{6}\z/) })
      assert_equal Source::ALL.map(&:color).uniq.length, Source::ALL.length
    end
  end
end
