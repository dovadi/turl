#!/usr/bin/env ruby

require 'rubygems'
require 'sequel'
require 'validatable'
require 'ramaze'

DB_FILE = File.join(File.dirname(__FILE__),"turl.db")
DB = Sequel.open("sqlite:///#{DB_FILE}")

BASE_URL = 'http://localhost:7000/'.freeze

#
#  Model
#
class TinyURL < Sequel::Model(:turl)
  set_schema do
    primary_key :id
    varchar     :url
    integer     :hits
    timestamp   :created
    index [:url], :unique => true
    index [:created]
    index [:hits]
  end

  include Validatable

  validates do
    presence_of :url
    format_of :url, :with =>
      /(^$)|(^(http|https):\/\/[a-z0-9]+([\-\.]{1}[a-z0-9]+)*\.[a-z]{2,5}(([0-9]{1,5})?\/.*)?$)/ix,
      :message => 'invalid URL'
  end

  after_create do
    update_values(:created => Time.now, :hits => 1)
  end

  def self.add(uri)
    t = TinyURL.create(:url => uri)
    return '' unless t.valid?
    t.save!
    return t.id.to_s(36)
  end

  def self.pack(uri,prefix=BASE_URL)
    return uri if uri.length < prefix.length
    exists = TinyURL[:url => uri]
    turl = exists ? exists.id.to_s(36) : TinyURL.add(uri)
    # 'index' is a controller name so insert the link once more
    turl = TinyURL.add(uri) if turl == 'index'
    return "#{prefix}#{turl}"
  end

  def self.unpack(turl)
    return nil unless t = TinyURL[:id => turl.to_i(36)]
    t.update_values(:hits => t.hits.to_i + 1)
    t.url
  end

end

TinyURL.create_table unless TinyURL.table_exists?

#
# Controller and View
#

class MainController < Ramaze::Controller

  LOGINS = {
    :admin => 'secret'
  }.map{|k,v| ["#{k}:#{v}"].pack('m').strip} unless defined? LOGINS

  helper :aspect

  before(:_api) do
    response['WWW-Authenticate'] = %(Basic realm="Login Required")
    respond 'Unauthorized', 401 unless auth = request.env['HTTP_AUTHORIZATION'] and
                                       LOGINS.include? auth.split.last
  end
  
  layout :_page

  def index turl=nil
    if turl
      url = TinyURL.unpack(turl)
      redirect(url ? url : Rs())
    end
    ""
  end

  def _add
    redirect(Rs()) unless request.post?
    turl = TinyURL.pack(request[:url])
    "Tiny URL: <a href=\"#{turl}\">#{turl}</a><br/><br/>"
  end

  # _api?url=http://... will return short url
  # _ari?turl=.. will restore the original url
  def _api
    res = TinyURL.pack(request[:url]) if request[:url]
    res = TinyURL.unpack(request[:turl].split('/').last) if request[:turl]
    res = '' unless res
    respond res
  end

  def _page
    %{
<html>
  <head>
    <title>TinyURL Service</title>
  </head>
  <body>
    #@content
    <form id="tinyurl" method="post" action="/_add">
      <div>
        Enter long URL: 
        <input id="url" name="url" type="text" />
        <input type="submit" value="Pack" />
      </div>
    </form>
  </body>
</html>
    }
  end
end

if __FILE__ == $0
  Ramaze.start :adapter => :thin, :port => 7000
end