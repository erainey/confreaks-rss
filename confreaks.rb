require 'bundler/setup'
Bundler.require
require 'sinatra'
require 'downloader'

configure do
  disable :lock
  set :server, :trinidad
  set :cache, ActiveSupport::Cache::DalliStore.new(expires_in: 12.hours)
  set :root, 'http://confreaks.com'
  set :user_agent, "Mozilla/5.0 (Macintosh; U; Intel Mac OS X 10_6_6; en-US) AppleWebKit/534.10 (KHTML, like Gecko) Chrome/8.0.552.237 Safari/534.10"
end

helpers do
  def get_url(url)
    settings.cache.fetch(url) { Excon.get(url) }
  end

  def video_size(size)
    number, order = size.split(' ')
    d = BigDecimal.new(number)
    d * (order.include?('MB') ? 1000000 : 1000000)
  end

  def video_page_to_xml(doc, size, xml)
    video_href = doc.search('.assets a').select { |a| a.text.include?(size) }.first
    return if video_href.nil?

    video = video_href[:href]
    title = doc.search('.video-title').text.strip
    author = doc.search('.video-presenters').text.strip
    conf = doc.search('div.center h3').text.strip
    description = doc.search('.video-abstract').to_html
    pubDate = Time.parse(doc.search('.video-posted-on strong').text.strip).rfc822

    details = video_href.text.split ' - '
    video_length = details.last
    file_length = details[-2]

    xml.item do
      xml.title("#{title} - #{author}")
      xml.author(author)
      xml.guid(video)
      xml.content(:encoded, description)
      xml.pubDate(pubDate)
      xml.itunes(:duration, video_length)
      xml.enclosure(:url => video, :length => video_size(file_length).to_i)
    end
  end

  def build_rss(url, title, size)
    resp = Downloader.new(settings.cache).get(url)
    presentation_urls = Nokogiri::HTML(resp.body).search('.title a').map { |a| settings.root + a[:href] }
    downloader_pool = Downloader.pool(size: 5, args: [settings.cache])
    future_docs = presentation_urls.map { |url| downloader_pool.future.get_and_parse(url) }

    builder = Builder::XmlMarkup.new
    builder.instruct!
    rss = builder.rss(version: '2.0',
                      "xmlns:itunes" => "http://www.itunes.com/dtds/podcast-1.0.dtd",
                      "xmlns:content" => "http://purl.org/rss/1.0/modules/content/") do |xml|
      xml.channel do
        xml.title("Confreaks - #{title} - #{size}p")
        xml.itunes(:image, href: 'http://cdn.confreaks.com/images/confreaks_logo.png')
        xml.link(url)
        xml.description("An RSS feed for #{title} with size matching #{size}")
        future_docs.each do |future|
          video_page_to_xml(future.value, size, xml)
        end
      end
    end
  rescue => boom
    logger.error(boom.message)
    halt 500, 'Error retrieving main conference page'
  end
end

get '/' do
  'Hello, World!'
end

get '/recent/:size' do |size|
  content_type :rss
  build_rss("#{settings.root}/videos", 'Recent', size)
end

get '/:conf/:size' do |conf, size|
  content_type :rss
  build_rss("#{settings.root}/events/#{conf}", conf, size)
end

