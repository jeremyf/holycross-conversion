#!/usr/bin/env ruby

require 'hpricot'
require 'yaml'
require 'logger'
require 'fileutils'
require 'rest_client'
require 'highline'
require 'fastercsv'
require "highline/import"

require File.join(File.dirname(__FILE__), 'database')

UPLOAD_SCHEME = 'https'
HOST = 'www.holycrossusa.org'

def net_id
  @net_id ||= ask(%(<%= color("Net ID: ", :black, :on_yellow)%>))
end

def password
  @password ||= ask(%(<%= color("Password: ", :black, :on_yellow)%>)) { |q| q.echo = "*" }
end

def with_rest_timeout_retry(counter)
  retried_counter = 0
  begin
    yield
  rescue RestClient::RequestTimeout => e
    if retried_counter < counter
      retried_counter += 1
      retry
    else
      raise e
    end
  end
end

init_db(true)

FileUtils.mkdir_p(File.join(File.dirname(__FILE__), '../log'))
log     = Logger.new(File.join(File.dirname(__FILE__), '../log', "#{File.basename(__FILE__)}.log"), 5, 10*1024)

image_directory = File.join(File.dirname(__FILE__), '../src/Headshots')
Dir.glob(File.join(image_directory, '**/*.*')).each do |filename|
  absolute_filename = File.expand_path(filename)
  next if Asset.find_by_local_filename(absolute_filename)
  Asset.transaction do
    asset = Asset.create(:local_filename => absolute_filename)
    with_rest_timeout_retry(3) do
      begin
        RestClient.post("#{UPLOAD_SCHEME}://#{net_id}:#{password}@#{File.join(HOST, "/admin/assets")}",
          {"asset" => { "file" => File.new(asset.local_filename), 'tag' => 'headshots' }, 'without_expire' => 'true', 'publish' => '1'}
        )
      rescue RestClient::Found => e
        uri = URI.parse(e.response.headers[:location])
        asset_id = uri.path.sub(/^\/admin\/assets\/(\d+)(\/.*)?/, '\1')
        asset.update_attribute(:conductor_asset_id, asset_id)
        log.info("Uploaded Asset #{asset.source_url}")
      rescue RestClient::InternalServerError => e
        log.error("Unable to Upload Asset #{asset.source_url}\n\t#{e}")
      end
    end
  end
end
