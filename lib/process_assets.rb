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

# UPLOAD_SCHEME = 'https'
# HOST = 'www.holycrossusa.org'

UPLOAD_SCHEME = 'http'
HOST = 'localhost:3000'

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

directory_filename = File.join(File.dirname(__FILE__), '../src/source_directory.csv')
image_directory = File.join(File.dirname(__FILE__), '../src/Headshots')

FasterCSV.foreach(directory_filename, :headers => true) do |row|
  if row['Photo'].to_s.strip.any?
    absolute_filename = File.expand_path(File.join(image_directory, row['Photo'].to_s.strip))
    next if Asset.find_by_local_filename(absolute_filename)
    if File.exist?(absolute_filename)
      Asset.transaction do
        asset = Asset.create(:local_filename => absolute_filename)
        descirptions = []
        descirptions << row['Prefix'].to_s.strip.gsub(/(\w)$/, '\1.')
        descirptions << row['Fname'].to_s.strip
        descirptions << row['Mname'].to_s.strip
        descirptions << row['Lname'].to_s.strip
        descirptions << row['Suffix'].to_s.strip
        puts title = descirptions.flatten.compact.select(&:any?).join(" ")
        with_rest_timeout_retry(3) do
          begin
            RestClient.post("#{UPLOAD_SCHEME}://#{net_id}:#{password}@#{File.join(HOST, "/admin/assets")}",
            {"asset" => { "file" => File.new(asset.local_filename), 'title' => title, 'tag' => 'headshots' }, 'without_expire' => 'true', 'publish' => '1'}
            )
          rescue RestClient::Found => e
            uri = URI.parse(e.response.headers[:location])
            asset_id = uri.path.sub(/^\/admin\/assets\/(\d+)(\/.*)?/, '\1')
            asset.update_attribute(:conductor_asset_id, asset_id)
            log.info("Uploaded Asset #{File.basename(asset.local_filename)}")
          rescue RestClient::InternalServerError => e
            log.error("Unable to Upload Asset #{asset.local_filename}\n\t#{e}")
          end
        end
      end
    else
      puts "Photo not found for #{row['Photo']}"
    end
  end
end

FasterCSV.open(File.join(File.dirname(directory_filename), 'target_directory.csv'), 'w+') do |csv|
  first_time = true
  FasterCSV.foreach(directory_filename, :headers => true) do |row|
    if first_time
      photo_column = row.headers.index("Photo")
      header = row.headers.clone
      header[photo_column] = "photo_upload"
      puts header.inspect
      csv << header
      first_time = false
    end
    photo_name = row['Photo'].to_s.strip
    if photo_name.any?
      if asset = Asset.find_by_local_filename(File.expand_path(File.join(image_directory, photo_name)))
        puts "updated #{photo_name}"
        row['Photo'] = asset.conductor_path
      end
    end
    working_row = row.inject([]) {|m,(k,v)|
      if v.nil?
        m << nil
      else
        m << v.to_s.strip
      end
    }
    csv << working_row
  end
end