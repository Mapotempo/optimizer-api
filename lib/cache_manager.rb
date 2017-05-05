class CacheManager
  attr_reader :cache

  def initialize(cache)
    @cache = cache
  end

  def read(name, options = nil)
    @cache.read(name, options)
  rescue StandardError => error
    Api::Root.logger.warn("Got error #{error} attempting to read cache #{name}.")
    return nil
  end

  def write(name, value, options = nil)
    @cache.write(name, value, options)
  rescue StandardError => error
    Api::Root.logger.warn("Got error #{error} attempting to write cache #{name}.")
    return nil
  end
end
