gem 'minitest'
require 'minitest/autorun'
require 'minitest/pride'
require 'minitest/mock'
require 'mocha/setup'
require 'commendo'

module Commendo

  class ContentSetTest < Minitest::Test

    def test_gives_similarity_key_for_resource
      redis = Redis.new(db: 15)
      key_base = 'CommendoTests'
      cs = ContentSet.new(redis, key_base)
      assert_equal 'CommendoTests:similar:resource-1', cs.similarity_key('resource-1')
    end

    def test_stores_sets_by_resource
      redis = Redis.new(db: 15)
      redis.flushdb
      key_base = 'CommendoTests'
      cs = ContentSet.new(redis, key_base)
      cs.add('resource-1', 'group-1', 'group-2')
      cs.add('resource-2', 'group-1')
      cs.add('resource-3', 'group-1', 'group-2')
      cs.add('resource-4', 'group-2')
      assert redis.sismember("#{key_base}:resources:resource-1", 'group-1')
      assert redis.sismember("#{key_base}:resources:resource-2", 'group-1')
      assert redis.sismember("#{key_base}:resources:resource-3", 'group-1')
      refute redis.sismember("#{key_base}:resources:resource-4", 'group-1')

      assert redis.sismember("#{key_base}:resources:resource-1", 'group-2')
      refute redis.sismember("#{key_base}:resources:resource-2", 'group-2')
      assert redis.sismember("#{key_base}:resources:resource-3", 'group-2')
      assert redis.sismember("#{key_base}:resources:resource-4", 'group-2')
    end

    def test_stores_sets_by_group
      redis = Redis.new(db: 15)
      redis.flushdb
      key_base = 'CommendoTests'
      cs = ContentSet.new(redis, key_base)
      cs.add_by_group('group-1', 'resource-1', 'resource-2', 'resource-3')
      cs.add_by_group('group-2', 'resource-1', 'resource-3', 'resource-4')
      assert redis.sismember("#{key_base}:resources:resource-1", 'group-1')
      assert redis.sismember("#{key_base}:resources:resource-2", 'group-1')
      assert redis.sismember("#{key_base}:resources:resource-3", 'group-1')
      refute redis.sismember("#{key_base}:resources:resource-4", 'group-1')

      assert redis.sismember("#{key_base}:resources:resource-1", 'group-2')
      refute redis.sismember("#{key_base}:resources:resource-2", 'group-2')
      assert redis.sismember("#{key_base}:resources:resource-3", 'group-2')
      assert redis.sismember("#{key_base}:resources:resource-4", 'group-2')
    end

    def test_calculates_similarity_scores
      redis = Redis.new(db: 15)
      redis.flushdb
      key_base = 'CommendoTests'
      cs = ContentSet.new(redis, key_base)
      (3..23).each do |group|
        (3..23).each do |res|
          cs.add_by_group(group, res) if res % group == 0
        end
      end
      cs.calculate_similarity
      expected = [
        { resource:  '9', similarity: 0.5 },
        { resource:  '6', similarity: 0.5 },
        { resource: '12', similarity: 0.33333333333333 },
        { resource:  '3', similarity: 0.25 },
        { resource: '21', similarity: 0.16666666666667 },
        { resource: '15', similarity: 0.16666666666667 }
      ]
      assert_equal expected, cs.similar_to(18)
    end

    def test_calculates_with_threshold
      redis = Redis.new(db: 15)
      redis.flushdb
      key_base = 'CommendoTests'
      cs = ContentSet.new(redis, key_base)
      (3..23).each do |group|
        (3..23).each do |res|
          cs.add_by_group(group, res) if res % group == 0
        end
      end
      cs.calculate_similarity(0.4)
      expected = [
        { resource:  '9', similarity: 0.5 },
        { resource:  '6', similarity: 0.5 },
      ]
      assert_equal expected, cs.similar_to(18)
    end

    def test_calculate_yields_after_each
      skip
    end

    def test_calculate_deletes_old_values_first
      skip
    end

    def test_deletes_resource_from_everywhere
      redis = Redis.new(db: 15)
      redis.flushdb
      key_base = 'CommendoTests'
      cs = ContentSet.new(redis, key_base)
      (3..23).each do |group|
        (3..23).each do |res|
          cs.add_by_group(group, res) if res % group == 0
        end
      end
      cs.calculate_similarity
      assert similar_to(cs, 18, 12)

      cs.delete(12)
      assert_equal [], cs.similar_to(12)
      refute similar_to(cs, 18, 12)

      cs.calculate_similarity
      assert_equal [], cs.similar_to(12)
      refute similar_to(cs, 18, 12)

    end

    def test_accepts_incremental_updates
      redis = Redis.new(db: 15)
      redis.flushdb
      key_base = 'CommendoTests'
      cs = ContentSet.new(redis, key_base)
      (3..23).each do |group|
        (3..23).each do |res|
          cs.add(res, group) if res % group == 0
        end
      end
      cs.calculate_similarity
      assert similar_to(cs, 18, 12)
      refute similar_to(cs, 10, 12)

      cs.add_and_calculate(12, 'foo', true)
      cs.add_and_calculate(10, 'foo', true)
      assert similar_to(cs, 10, 12)
    end

    def test_accepts_tag_collection
      skip
    end

    def test_filters_by_tag_collection
      skip
    end

    def similar_to(cs, resource, similar)
      cs.similar_to(resource).select { |sim| sim[:resource] == "#{similar}" }.length > 0
    end

  end

end