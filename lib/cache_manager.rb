require 'fileutils'

class CacheError < StandardError; end

class CacheManager
  attr_reader :cache

  def initialize(cache)
    @cache = cache
    @filesize_limit = 50 # in megabytes
    FileUtils.mkdir_p(@cache)
  end

  def read(name, _options = nil)
    filtered_name = name.to_s.parameterize(separator: '')
    if File.exist?(File.join(@cache, filtered_name))
      File.read(File.join(@cache, filtered_name), mode: 'r')
    end
  rescue StandardError => e
    raise CacheError, "Got error #{e} attempting to read cache #{name}." if !cache.is_a? ActiveSupport::Cache::NullStore
  end

  def write(name, value, options = { mode: 'w' })
    raise CacheError, 'Stored value is not a String' if !value.is_a? String

    File.open(File.join(@cache, name.to_s.parameterize(separator: '')), options[:mode]) do |f|
      if value.bytesize < @filesize_limit.megabytes
        f.write(value)
      else
        f.write("File size is greater than #{@filesize_limit} Mb.")
      end
    end
  rescue StandardError => e
    raise CacheError, "Got error #{e} attempting to write cache #{name}." if !cache.is_a? ActiveSupport::Cache::NullStore
  end

  def cleanup(options = nil)
    @cache.cleanup(options)
  rescue StandardError => e
    raise CacheError, "Got error #{e} attempting to clean cache." if !cache.is_a? ActiveSupport::Cache::NullStore
  end
end
