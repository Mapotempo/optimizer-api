# Copyright © Mapotempo, 2017
#
# This file is part of Mapotempo.
#
# Mapotempo is free software. You can redistribute it and/or
# modify since you respect the terms of the GNU Affero General
# Public License as published by the Free Software Foundation,
# either version 3 of the License, or (at your option) any later version.
#
# Mapotempo is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
# or FITNESS FOR A PARTICULAR PURPOSE.  See the Licenses for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with Mapotempo. If not, see:
# <http://www.gnu.org/licenses/agpl.html>
#

class CacheError < StandardError; end

class CacheManager
  attr_reader :cache

  def initialize(cache)
    @cache = cache
    @data_bytesize_limit_in_mb = 500 # in megabytes
    FileUtils.mkdir_p(@cache)
  end

  def read(name, _options = nil)
    filtered_name = name.to_s.parameterize(separator: '')
    if File.exist?(File.join(@cache, filtered_name) + '.gz') # Gzip dumps
      Zlib::GzipReader.open(File.join(@cache, filtered_name) + '.gz', &:read)
    elsif File.exist?(File.join(@cache, filtered_name)) # Zlib (and uncompressed) dumps
      content = File.read(File.join(@cache, filtered_name), mode: 'r')
      begin
        Zlib::Inflate.inflate(content)
      rescue Zlib::DataError # Previously dumped files were not compressed, protect them with a fallback
        content
      end
    end
  rescue StandardError => e
    if !cache.is_a? ActiveSupport::Cache::NullStore
      raise CacheError.new("Got error \"#{e}\" attempting to read cache \"#{name}\".")
    end
  end

  def write(name, value, mode = 'w', gz = true)
    raise CacheError.new('Stored value is not a String') if !value.is_a? String

    if gz
      File.open(File.join(@cache, name.to_s.parameterize(separator: '')) + '.gz', mode) do |f|
        gz = Zlib::GzipWriter.new(f)
        if value.bytesize < @data_bytesize_limit_in_mb.megabytes
          gz.write value
        else
          gz.write "Data size is greater than #{@data_bytesize_limit_in_mb} Mb."
        end
        gz.close
      end
    else
      File.write(File.join(@cache, name.to_s), value, mode: mode)
    end
  rescue StandardError => e
    if !cache.is_a? ActiveSupport::Cache::NullStore
      raise CacheError.new("Got error \"#{e}\" attempting to write cache \"#{name}\".")
    end
  end

  def cleanup(options = nil)
    @cache.cleanup(options)
  rescue StandardError => e
    if !cache.is_a? ActiveSupport::Cache::NullStore
      raise CacheError.new("Got error \"#{e}\" attempting to clean cache.")
    end
  end
end
