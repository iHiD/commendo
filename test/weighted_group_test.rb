gem 'minitest'
require 'minitest/autorun'
require 'minitest/pride'
require 'minitest/mock'
require 'mocha/setup'
require 'commendo'

module Commendo

  class WeightedGroupTest < Minitest::Test

    def test_calls_each_content_set
      redis = Redis.new(db: 15)
      redis.flushdb
      cs1 = ContentSet.new(redis, 'CommendoTests:ContentSet1')
      cs2 = ContentSet.new(redis, 'CommendoTests:ContentSet2')
      cs3 = ContentSet.new(redis, 'CommendoTests:ContentSet3')
      (3..23).each do |group|
        (3..23).each do |res|
          cs1.add_by_group(group, res) if (res % group == 0) && (res % 2 == 0)
          cs2.add_by_group(group, res) if (res % group == 0) && (res % 3 == 0)
          cs3.add_by_group(group, res) if (res % group == 0) && (res % 6 == 0)
        end
      end
      [cs1, cs2, cs3].each { |cs| cs.calculate_similarity }
      weighted_group = WeightedGroup.new(redis, 'CommendoTests:WeightedGroup', { cs: cs1, weight: 1.0 },  { cs: cs2, weight: 10.0 },  { cs: cs3, weight: 100.0 } )
      expected = [
        {resource: '6', similarity: 55.5},
        {resource: '12', similarity: 37.0},
        {resource: '9', similarity: 5.0},
        {resource: '3', similarity: 2.5},
        {resource: '21', similarity: 1.6666666666666665},
        {resource: '15', similarity: 1.6666666666666665}
      ]
      assert_equal expected, weighted_group.similar_to(18)
    end

    def test_precalculates
      skip
    end



  end

end
