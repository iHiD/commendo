module Commendo

  class ContentSet

    attr_accessor :redis, :key_base, :tag_set

    def initialize(redis, key_base, tag_set = nil)
      @redis, @key_base, @tag_set = redis, key_base, tag_set
    end

    def add_by_group(group, *resources)
      resources.each do |resource|
        if resource.kind_of?(Array)
          add_single(resource[0], group, resource[1])
        else
          add_single(resource, group, 1)
        end
      end
    end

    def add(resource, *groups)
      groups.each do |group|
        if group.kind_of?(Array)
          add_single(resource, group[0], group[1])
        else
          add_single(resource, group, 1)
        end
      end
    end

    def add_single(resource, group, score)
      redis.zincrby(group_key(group), score, resource)
      redis.zincrby(resource_key(resource), score, group)
    end

    def add_and_calculate(resource, *groups)
      add(resource, *groups)
      calculate_similarity_for_resource(resource, 0)
    end

    def delete(resource)
      similar = similar_to(resource)
      similar.each do |other_resource|
        redis.zrem(similarity_key(other_resource[:resource]), "#{resource}")
      end
      #TODO delete from groups?
      redis.del(similarity_key(resource))
      redis.del(resource_key(resource))
    end

    SET_TOO_LARGE_FOR_LUA = 999

    def calculate_similarity(threshold = 0)
      #TODO make this use scan for scaling
      keys = redis.keys("#{resource_key_base}:*")
      keys.each_with_index do |key, i|
        yield(key, i, keys.length) if block_given?
        completed = redis.eval(similarity_lua, keys: [key], argv: [tmp_key_base, resource_key_base, similar_key_base, group_key_base, threshold])
        if completed == SET_TOO_LARGE_FOR_LUA
          calculate_similarity_for_key(key, threshold)
        end
      end
    end

    def calculate_similarity_for_key(key, threshold)
      resource = key.gsub(/^#{resource_key_base}:/, '')
      calculate_similarity_for_key_resource(key, resource, threshold)
    end

    def calculate_similarity_for_resource(resource, threshold)
      key = resource_key(resource)
      calculate_similarity_for_key_resource(key, resource, threshold)
    end

    def calculate_similarity_for_key_resource(key, resource, threshold)
      groups = redis.zrange(resource_key(resource), 0, -1)
      group_keys = groups.map { |group| group_key(group) }
      tmp_key = "#{tmp_key_base}:#{SecureRandom.uuid}"
      redis.zunionstore(tmp_key, group_keys)
      resources = redis.zrange(tmp_key, 0, -1)
      redis.del(tmp_key)
      resources.each do |to_compare|
        next if resource == to_compare
        redis.eval(pair_comparison_lua, keys: [key, resource_key(to_compare), similarity_key(resource), similarity_key(to_compare)], argv: [tmp_key_base, resource, to_compare, threshold])
      end
    end

    def similar_to(resource)
      if resource.kind_of? Array
        keys = resource.map do |res|
          similarity_key(res)
        end
        tmp_key = "#{key_base}:tmp:#{SecureRandom.uuid}"
        redis.zunionstore(tmp_key, keys)
        similar_resources = redis.zrevrange(tmp_key, 0, -1, with_scores: true)
        redis.del(tmp_key)
      else
        similar_resources = redis.zrevrange(similarity_key(resource), 0, -1, with_scores: true)
      end
      similar_resources.map do |resource|
        {resource: resource[0], similarity: resource[1].to_f}
      end
    end

    def filtered_similar_to(resource, options = {})
      similar = similar_to(resource)
      return similar if @tag_set.nil? || options[:include].nil? && options[:exclude].nil?
      similar.delete_if { |s| !options[:exclude].nil? && @tag_set.matches(s[:resource], *options[:exclude]) }
      similar.delete_if { |s| !options[:include].nil? && !@tag_set.matches(s[:resource], *options[:include]) }
      similar
    end

    def similarity_key(resource)
      "#{similar_key_base}:#{resource}"
    end

    private

    def similarity_lua
      @similarity_lua ||= load_similarity_lua
    end

    def load_similarity_lua
      file = File.open(File.expand_path('../similarity.lua', __FILE__), "r")
      file.read
    end

    def pair_comparison_lua
      @pair_comparison_lua ||= load_pair_comparison_lua
    end

    def load_pair_comparison_lua
      file = File.open(File.expand_path('../pair_comparison.lua', __FILE__), "r")
      file.read
    end

    def tmp_key_base
      "#{key_base}:tmp"
    end

    def similar_key_base
      "#{key_base}:similar"
    end

    def resource_key_base
      "#{key_base}:resources"
    end

    def resource_key(resource)
      "#{resource_key_base}:#{resource}"
    end

    def group_key_base
      "#{key_base}:groups"
    end

    def group_key(group)
      "#{group_key_base}:#{group}"
    end

  end

end