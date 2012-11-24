require 'celluloid'

class Downloader
  include Celluloid

  attr_reader :cache

  def initialize(cache)
    @cache = cache
  end

  def get(url)
    cache.fetch(url) { RestClient.get(url) }
  end

  def get_and_parse(url)
    Nokogiri::HTML(get(url))
  end
end
