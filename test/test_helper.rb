require 'test/unit'
require 'rubygems'
require 'active_record'
require 'active_record/fixtures'
require 'active_support'
require 'active_support/test_case'

require File.dirname(__FILE__) + '/../lib/ez/where'
require File.dirname(__FILE__) + '/../lib/ez/clause'
require File.dirname(__FILE__) + '/../lib/ez/condition'
require File.dirname(__FILE__) + '/../lib/ez/hash'
require File.dirname(__FILE__) + '/../lib/ez/compositions'

$KCODE = 'u' if RUBY_VERSION < '1.9'

config = YAML::load(IO.read(File.dirname(__FILE__) + '/database.yml'))
ActiveRecord::Base.logger = Logger.new(File.dirname(__FILE__) + "/debug.log")

driver = config[ENV['db'] ? ENV['db'] : 'sqlite3']

ActiveRecord::Base.establish_connection(driver)

ActiveRecord::Base.logger = Logger.new(File.dirname(__FILE__) + "/debug.log")

ActiveRecord::Base.logger.silence { load(File.dirname(__FILE__) + "/schema.rb") }

#old & obsolete? $LOAD_PATH.unshift(Test::Unit::TestCase.fixture_path)

class ActiveSupport::TestCase
  include ActiveRecord::TestFixtures

  self.fixture_path = File.dirname(__FILE__) + "/fixtures/"
  self.use_instantiated_fixtures  = false
  self.use_transactional_fixtures = true

  def create_fixtures(*table_names, &block)
    Fixtures.create_fixtures(ActiveSupport::TestCase.fixture_path, table_names, {}, &block)
  end

  class<<self
    alias fixtures_before_ezwhere fixtures
  end

  def self.fixtures(*args)
    fixtures_before_ezwhere(*args)
    # why isn't the fixtures method creating the fixtures?
    Fixtures.create_fixtures(ActiveSupport::TestCase.fixture_path, args)
  end

end

class Article < ActiveRecord::Base

  belongs_to :author
  has_many   :comments

end

class Author < ActiveRecord::Base

  has_many :articles

end

class Comment < ActiveRecord::Base

  belongs_to :articles
  belongs_to :user

end

class User < ActiveRecord::Base

  has_many :comments

end