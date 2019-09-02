require 'fileutils'

class CacheManager
  attr_reader :cache

  def initialize(cache)
    @cache = cache
  end

  def read(name, options = nil)
    if File.exist?(name)
      File.open(File.join(@cache, name.parameterize(separator: '')), "r")
    end
  rescue StandardError => error
    Api::Root.logger.warn("Got error #{error} attempting to read cache #{name}.")
    return nil
  end

  def write(name, value, options = nil)
    FileUtils.mkdir_p(@cache)
    f = File.new(File.join(@cache, name.parameterize(separator: '')), "w")
    f.write(value) if value.to_s.bytesize < 100.megabytes
    f.close
  rescue StandardError => error
    Api::Root.logger.warn("Got error #{error} attempting to write cache #{name}.")
    return nil
  end

  def cleanup(options = nil)
    @cache.cleanup(options)
    return nil
  end
end
