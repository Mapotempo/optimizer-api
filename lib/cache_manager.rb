require 'fileutils'

class CacheManager
  attr_reader :cache

  def initialize(cache)
    @cache = cache
  end

  def read(name, options = nil)
    filtered_name = name.parameterize(separator: '')
    if File.exist?(File.join(@cache, filtered_name))
      File.open(File.join(@cache, filtered_name), 'r').read
    end
  rescue StandardError => e
    raise CacheError.new("Got error #{e} attempting to read cache #{name}.") if !cache.is_a? ActiveSupport::Cache::NullStore
  end

  def write(name, value, _options = nil)
    raise CacheError.new('Stored value is not a String') if !value.is_a? String

    FileUtils.mkdir_p(@cache)
    f = File.new(File.join(@cache, name.parameterize(separator: '')), 'w')
    f.write(value) if value.to_s.bytesize < 100.megabytes
    f.close
  rescue StandardError => e
    raise CacheError.new("Got error #{e} attempting to write cache #{name}.") if !cache.is_a? ActiveSupport::Cache::NullStore
  end

  def cleanup(options = nil)
    @cache.cleanup(options)
  rescue StandardError => e
    raise CacheError.new("Got error #{e} attempting to clean cache.") if !cache.is_a? ActiveSupport::Cache::NullStore
  end
end
