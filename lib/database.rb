require 'active_record'

ActiveRecord::Base.logger = Logger.new(STDERR)
ActiveRecord::Base.colorize_logging = false

ActiveRecord::Base.establish_connection(
:adapter => "sqlite3",
:database => 'database.sqlite'

)


def init_db(force = false)
  ActiveRecord::Schema.define do
    create_table :assets, :force => force do |table|
      table.column :conductor_asset_id, :integer
      table.column :local_filename, :text
    end
  end
end


class Asset < ActiveRecord::Base
  def conductor_path
    "/assets/#{conductor_asset_id}/#{File.basename(local_filename)}"
  end
end