require 'fileutils'
require 'zlib'

class CacheError < StandardError; end

class CacheManager
  attr_reader :cache

  def initialize(cache)
    @cache = cache
    @filesize_limit = 100 # in megabytes
    FileUtils.mkdir_p(@cache)
  end

  def read(name, _options = nil)
    filtered_name = name.to_s.parameterize(separator: '')
    if File.exist?(File.join(@cache, filtered_name))
      content = File.read(File.join(@cache, filtered_name), mode: 'r')
      begin
        Zlib::Inflate.inflate(content)
      rescue Zlib::DataError # Previously dumped files were not compressed, protect them
        content
      end
    end
  rescue StandardError => e
    raise CacheError, "Got error #{e} attempting to read cache #{name}." if !cache.is_a? ActiveSupport::Cache::NullStore
  end

  def write(name, value, options = { mode: 'w' })
    raise CacheError, 'Stored value is not a String' if !value.is_a? String

    File.open(File.join(@cache, name.to_s.parameterize(separator: '')), options[:mode]) do |f|
      compressed = Zlib::Deflate.deflate(value)
      if compressed.bytesize < @filesize_limit.megabytes
        f.write(compressed)
      else
        f.write("File size is greater than #{@filesize_limit} Mb after compression.")
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
