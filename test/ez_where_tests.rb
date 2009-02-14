require File.dirname(__FILE__) + '/test_helper'

class PluralizeClause < EZ::Where::AbstractClause

  def initialize(name, value)
    @outer = :and
    @test = :pluralize
    @name, @value = name, value
  end

  def to_sql
    cond = EZ::Where::Condition.new :inner => :or
    cond.clause(@name) == @value.singularize
    cond.clause(@name) == @value.singularize.pluralize
    cond.to_sql
  end

  def empty?
    @value.to_s.empty?
  end

end

module EZ::Where::Compositions
  
  class Active < Base  
    def prepare(klass)
      active  == true  if klass.column_names.include? 'active'
      visible == true  if klass.column_names.include? 'visible'
      hidden  == false if klass.column_names.include? 'hidden'
      deactivated_at == :null if klass.column_names.include? 'deactivated_at'
    end  
  end
  
  class Published < Base
    def prepare(klass, now = Time.new)
      append Active.new(klass)
      date_cond = create_condition
      date_cond += c { publish_at == :null; unpublish_at == :null }
      date_cond |= c { publish_at <= now } + (c { unpublish_at > now } | c { unpublish_at == :null })
      append date_cond
    end
  end
  
end

class SampleToCond
    
  def to_cond
    c(self.class.to_s.tableize) { hidden == false }
  end
  
  def self.to_cond
    c(self.to_s.tableize) { active == true }
  end
  
end

class EZWhereTest < Test::Unit::TestCase

  fixtures :articles, :authors, :comments, :users

  def test_ez_where
    cond = EZ::Where::Condition.new do
      foo == 'bar'
      baz <=> (1..5)
      id === [1, 2, 3, 5, 8]
    end

    expected = ["foo = ? AND (baz BETWEEN ? AND ?) AND id IN (?)", "bar", 1, 5, [1, 2, 3, 5, 8]]
    assert_equal expected, cond.to_sql

    cond = EZ::Where::Condition.new :my_table do
      foo == 'bar'
      baz <=> (1..5)
      id === [1, 2, 3, 5, 8]
    end

    expected = ["my_table.foo = ? AND (my_table.baz BETWEEN ? AND ?) AND my_table.id IN (?)", "bar", 1, 5, [1, 2, 3, 5, 8]]
    assert_equal expected, cond.to_sql

    cond = EZ::Where::Condition.new :my_table do
      foo == 'bar'
      baz <=> (1..5)
      id === [1, 2, 3, 5, 8]
      condition :my_other_table do
        fiz =~ '%faz%'
      end
    end

    expected = ["my_table.foo = ? AND (my_table.baz BETWEEN ? AND ?) AND my_table.id IN (?) AND (my_other_table.fiz LIKE ?)", "bar", 1, 5, [1, 2, 3, 5, 8], "%faz%"]
    assert_equal expected, cond.to_sql

    cond = EZ::Where::Condition.new :my_table do
      foo == 'bar'
      baz <=> (1..5)
      id === [1, 2, 3, 5, 8]
      condition :my_other_table do
        fiz =~ '%faz%'
      end
    end

    expected = ["my_table.foo = ? AND (my_table.baz BETWEEN ? AND ?) AND my_table.id IN (?) AND (my_other_table.fiz LIKE ?)", "bar", 1, 5, [1, 2, 3, 5, 8], "%faz%"]
    assert_equal expected, cond.to_sql

    cond_a = EZ::Where::Condition.new :my_table do
      foo == 'bar'
      condition :my_other_table do
        id === [1, 3, 8]
        foo == 'other bar'
        fiz =~ '%faz%'
      end
    end

    expected = ["my_table.foo = ? AND (my_other_table.id IN (?) AND my_other_table.foo = ? AND my_other_table.fiz LIKE ?)", "bar", [1, 3, 8], "other bar", "%faz%"]
    assert_equal expected, cond_a.to_sql

    cond_b = EZ::Where::Condition.new :my_table do
      active == true
      archived == false
    end

    expected = ["my_table.active = ? AND my_table.archived = ?", true, false]
    assert_equal expected, cond_b.to_sql

    composed_cond = EZ::Where::Condition.new
    composed_cond << cond_a
    composed_cond << cond_b.to_sql
    composed_cond << 'fuzz IS NULL'

    expected = ["(my_table.foo = ? AND (my_other_table.id IN (?) AND my_other_table.foo = ? AND my_other_table.fiz LIKE ?)) AND (my_table.active = ? AND my_table.archived = ?) AND fuzz IS NULL", "bar", [1, 3, 8], "other bar", "%faz%", true, false]
    assert_equal expected, composed_cond.to_sql

    cond = EZ::Where::Condition.new :my_table do
      foo == 'bar'
      any :my_other_table do
        baz === ['fizz', 'fuzz']
        biz == 'boz'
      end
    end

    expected = ["my_table.foo = ? AND (my_other_table.baz IN (?) OR my_other_table.biz = ?)", "bar", ["fizz", "fuzz"], "boz"]
    assert_equal expected, cond.to_sql

    cond = EZ::Where::Condition.new :my_table do
      foo == 'bar'
      any do
        baz === ['fizz', 'fuzz']
        biz == 'boz'
      end
    end

    expected = ["my_table.foo = ? AND (my_table.baz IN (?) OR my_table.biz = ?)", "bar", ["fizz", "fuzz"], "boz"]
    assert_equal expected, cond.to_sql

    cond = EZ::Where::Condition.new do
      foo == 'bar'
      any do
        baz === ['fizz', 'fuzz']
        biz == 'boz'
      end
    end

    expected = ["foo = ? AND (baz IN (?) OR biz = ?)", "bar", ["fizz", "fuzz"], "boz"]
    assert_equal expected, cond.to_sql

    cond = EZ::Where::Condition.new do
      foo == 'bar'
      add_sql ['baz = ? AND bar IS NOT NULL', 'fuzz']
    end

    expected = ["foo = ? AND (baz = ? AND bar IS NOT NULL)", "bar", "fuzz"]
    assert_equal expected, cond.to_sql

    cond = EZ::Where::Condition.new
    cond.foo == 'bar'
    cond << ['baz = ? AND bar IS NOT NULL', 'fuzz']

    expected = ["foo = ? AND (baz = ? AND bar IS NOT NULL)", "bar", "fuzz"]
    assert_equal expected, cond.to_sql
  end

  def test_compose_condition
    ar_instance = Author.find(1)

    other_cond = EZ::Where::Condition.new :my_table do
      foo == 'bar'; baz == 'buzz'
    end

    cond = EZ::Where::Condition.new
    # another Condition
    cond.append other_cond
    # an array in AR condition format
    cond.append ['baz = ? AND bar IS NOT NULL', 'fuzz'], :or
    # a raw SQL string
    cond.append 'biz IS NULL'
    # an Active Record instance from DB or as Value Object
    cond.append ar_instance

    expected = ["(my_table.foo = ? AND my_table.baz = ?) OR (baz = ? AND bar IS NOT NULL) AND biz IS NULL AND (authors.id = ?)", "bar", "buzz", "fuzz", 1]
    assert_equal expected, cond.to_sql
  end

  def test_find_where
    articles = Article.find_where(:all, :conditions => ['authors.id = ?', 1], :include => :author, :limit => 1)
    assert_equal 1, articles.length

    articles = Article.find_where(:all, :include => :author, :limit => 1) do |article, author|
      author.id == 1
    end
    assert_equal 1, articles.length

    articles = Article.find_where(:all, :include => :author) do |article, author|
      article.title =~ "Wh%"
    end
    assert_equal 2, articles.length

    articles = Article.find_where(:all, :include => :author) do |article, author|
      article.title =~ "Wh%"
      author.id == 1
    end
    assert_equal 1, articles.length

    articles = Article.find_where(:all, :include => :author, :limit => 1) do |article, author|
      author.name =~ 'Ez%'
    end
    assert_equal 1, articles.length
  end

  def test_find_where_with_more_complex_queries
    ezra = Author.find(2)

    # all articles written by Ezra
    articles = Article.find_where(:all, :include => :author) do |article, author|
      author << ezra # use AR instance to add condition; uses PK value if set: author.id = ezra.id
    end
    assert articles.length >= 1

    # all articles written by Ezra, where he himself responds in comments
    articles = Article.find_where(:all, :include => [:author, :comments]) do |article, author, comment|
      article.author_id == ezra.id
      comment.user_id == ezra.id
    end
    assert_equal 1, articles.length

    # any articles written by Fab or Ezra
    articles = Article.find_where(:all, :include => :author) do |article, author|
      author.name === ['Fab', 'Ezra']
    end
    assert articles.length >= 1

    # any articles written by Fab or Ezra, using subcondition
    articles = Article.find_where(:all, :include => :author) do |article, author|
      author.any do
        name == 'Ezra'
        name == 'Fab'
      end
    end
    assert articles.length >= 1

    # any articles written by or commented on by Fab, using subcondition
    articles = Article.find_where(:all, :include => [:author, :comments]) do |article, author, comment|
      article.author_id == 1
      comment.outer = :or # set :outer for the comment condition, since it defaults to :and
      comment.user_id == 1
    end
    assert articles.length >= 1
  end

  def test_find_where_with_outer_and_inner_mapping
    # any articles written by Fab or Ezra or commented on by Fab, using subcondition and preset :outer and :inner
    articles = Article.find_where(:all, :include => [:author, :comments], :outer => { :comments => :or }, :inner => { :article => :or }) do |article, author, comment|
      article.author_id == 1
      article.author_id == 2
      comment.user_id == 1
    end
    assert articles.length >= 1
  end

  def test_where_condition
    cond = Article.where_condition { active == true; archived == false }
    cond.any { title =~ '%article%'; title =~ '%first%' }

    expected = ["articles.active = ? AND articles.archived = ? AND (articles.title LIKE ? OR articles.title LIKE ?)",
      true,
      false,
      "%article%",
    "%first%"]
    assert_equal expected, cond.to_sql

    cond = Article.where_condition { active == true; archived == false }
    cond.all { body =~ '%intro%'; body =~ '%demo%' }
    cond.any { title =~ '%article%'; title =~ '%first%' }

    expected = ["articles.active = ? AND articles.archived = ? AND (articles.body LIKE ? AND articles.body LIKE ?) AND (articles.title LIKE ? OR articles.title LIKE ?)",
      true,
      false,
      "%intro%",
      "%demo%",
      "%article%",
    "%first%"]
    assert_equal expected, cond.to_sql
  end
  
  def test_negate_ez_where
    cond = EZ::Where::Condition.new :my_table do
      foo! == 'bar'
      baz! <=> (1..5)
      id! === [1, 2, 3, 5, 8]
    end
    expected = ["my_table.foo != ? AND (my_table.baz NOT BETWEEN ? AND ?) AND my_table.id NOT IN (?)", "bar", 1, 5, [1, 2, 3, 5, 8]]
    assert_equal expected, cond.to_sql
  end

  def test_negate_condition
    cond = EZ::Where::Condition.new :my_table do
      any { foo == 'bar'; name == 'rails' }
      all { baz! == 'buzz'; name! == 'loob' }
    end
    expected = ["(my_table.foo = ? OR my_table.name = ?) AND (my_table.baz != ? AND my_table.name != ?)", "bar", "rails", "buzz", "loob"]
    assert_equal expected, cond.to_sql(:not)
  end

  def test_regexp_condition
    cond = EZ::Where::Condition.new :my_table do
      foo =~ /^bar/
      baz =~ /^([a-z_]+)$/
    end
    assert_equal ["my_table.foo REGEXP ? AND my_table.baz REGEXP ?", "^bar", "^([a-z_]+)$"], cond.to_sql
  end

  def test_complex_sub_condition
    cond = EZ::Where::Condition.new :my_table do
      any { foo == 'bar'; name == 'rails' }
      sub :table_name => :my_other_table, :outer => :and, :inner => :or do
        all { fud == 'bar'; flip == 'rails' }
        sub :outer => :not, :inner => :or do
          color == 'yellow'
          finish == 'glossy'
          sub :outer => :or do
            baz == 'buzz'
            name == 'loob'
          end
        end
      end
    end
    expected = ["(my_table.foo = ? OR my_table.name = ?) AND ((my_other_table.fud = ? AND my_other_table.flip = ?) AND NOT (my_other_table.color = ? OR my_other_table.finish = ? OR (my_other_table.baz = ? AND my_other_table.name = ?)))",
      "bar",
      "rails",
      "bar",
      "rails",
      "yellow",
      "glossy",
      "buzz",
    "loob"]
    assert_equal expected, cond.to_sql
  end

  def test_define_sub_condition_syntax_refinements

    # these are here to stir the discussion on the final public API methods

    cond1 = EZ::Where::Condition.new :my_table do
      foo == 'bar'
      any do
        baz === ['fizz', 'fuzz']
        biz == 'boz'
      end
    end

    cond2 = EZ::Where::Condition.new :my_table do
      foo == 'bar'
      sub :outer => :and, :inner => :or do
        baz === ['fizz', 'fuzz']
        biz == 'boz'
      end
    end

    cond3 = EZ::Where::Condition.new :my_table do
      foo == 'bar'
      my_table :outer => :and, :inner => :or do
        baz === ['fizz', 'fuzz']
        biz == 'boz'
      end
    end

    expected = ["my_table.foo = ? AND (my_table.baz IN (?) OR my_table.biz = ?)", "bar", ["fizz", "fuzz"], "boz"]
    assert_equal cond1.to_sql, cond2.to_sql
    assert_equal cond1.to_sql, cond3.to_sql
    assert_equal expected, cond1.to_sql

    cond = EZ::Where::Condition.new :my_table do
      foo == 'bar'
      my_table :outer => :or do
        baz == 'fuzz'
        biz == 'boz'
      end
    end

    expected = ["my_table.foo = ? OR (my_table.baz = ? AND my_table.biz = ?)", "bar", "fuzz", "boz"]
    assert_equal expected, cond.to_sql

    cond1 = EZ::Where::Condition.new :my_table do
      foo == 'bar'
      my_table do
        baz == 'fuzz'
        biz == 'boz'
      end
    end

    cond2 = EZ::Where::Condition.new :my_table do
      foo == 'bar'
      sub do
        baz == 'fuzz'
        biz == 'boz'
      end
    end

    expected = ["my_table.foo = ? AND (my_table.baz = ? AND my_table.biz = ?)", "bar", "fuzz", "boz"]
    assert_equal cond1.to_sql, cond2.to_sql
    assert_equal expected, cond1.to_sql
  end

  def test_clause_method
    cond = EZ::Where::Condition.new :my_table
    cond.clause(:foo) == 'bar'
    cond.clause(:baz) <=> (1..5)
    cond.clause(:id) === [1, 2, 3, 5, 8]

    expected = ["my_table.foo = ? AND (my_table.baz BETWEEN ? AND ?) AND my_table.id IN (?)", "bar", 1, 5, [1, 2, 3, 5, 8]]
    assert_equal expected, cond.to_sql

    cond = EZ::Where::Condition.new :my_table
    cond.clause(:foo!) == 'bar'
    cond.clause(:baz) == 'buzz'
    expected = ["my_table.foo != ? AND my_table.baz = ?", "bar", "buzz"]
    assert_equal expected, cond.to_sql
  end

  def test_null_value_to_sql
    cond = EZ::Where::Condition.new :my_table do
      any { foo == 'bar'; name == 'rails' }
      all { baz == :null; name! == :null }
    end
    expected = ["(my_table.foo = ? OR my_table.name = ?) AND (my_table.baz IS NULL AND my_table.name IS NOT NULL)", "bar", "rails"]
    assert_equal expected, cond.to_sql
  end

  def test_clone_from_active_record_instance
    author = Author.find(2)

    # AR instance as Value Object
    article = Article.new do |a|
      a.title = 'Article One'
      a.author = author # convenient...
    end

    assert_equal 2, article.author_id

    cond = EZ::Where::Condition.new
    cond.clone_from article

    expected = ["(articles.title = ? AND articles.author_id = ? AND articles.hidden = ? AND articles.active = ?)", "Article One", 2, 0, 1]
    assert_equal expected, cond.to_sql

    cond = EZ::Where::Condition.new
    cond << article
    assert_equal expected, cond.to_sql

    # AR instance, based on primary key only
    cond = EZ::Where::Condition.new
    cond << author
    cond << Article.find(1)

    expected = ["(authors.id = ?) AND (articles.id = ?)", 2, 1]
    assert_equal expected, cond.to_sql
  end

  def test_custom_clause_class
    cond = EZ::Where::Condition.new :my_table
    cond << PluralizeClause.new('column', 'person')
    cond << PluralizeClause.new('other_column', 'car')
    cond << PluralizeClause.new('another_column', 'house')
    expected = ["(column = ? OR column = ?) AND (other_column = ? OR other_column = ?) AND (another_column = ? OR another_column = ?)", "person", "people", "car", "cars", "house", "houses"]
    assert_equal expected, cond.to_sql
  end

  def test_conditions_hash
    sql = { 'name' => 'fab', 'country' => 'Belgium' }.to_sql
    assert_equal "name = 'fab' AND country = 'Belgium'", sql

    conditions = { 'name' => 'fab', 'country' => 'Belgium' }.to_conditions
    assert_equal ["name = ? AND country = ?", "fab", "Belgium"], conditions

    cond = EZ::Where::Condition.new :my_table
    cond.any { foo == 'bar'; name == 'rails' }
    cond.append 'name' => 'fab', 'country' => 'Belgium'
    expected = ["(my_table.foo = ? OR my_table.name = ?) AND (name = ? AND country = ?)", "bar", "rails", "fab", "Belgium"]
    assert_equal expected, cond.to_sql
  end

  def test_append_class_constant_for_sti
    cond_a = EZ::Where::Condition.new
    cond_a << Article

    expected = ["(articles.type = ?)", "Article"]
    assert_nil cond_a.to_sql

    cond = EZ::Where::Condition.new
    cond << Article.find(1)

    expected = ["(articles.id = ?)", 1]
    assert_equal expected, cond.to_sql
  end

  def test_soundex_clause
    cond = EZ::Where::Condition.new :my_table, :inner => :or
    cond.name % '%fab%'
    expected = ["my_table.name SOUNDS LIKE ?", "%fab%"]
    assert_equal expected, cond.to_sql
  end

  def test_conditions_from_params_and_example
    params = { 'title' => 'package', 'body' => nil, 'author' => 'Fab' }

    articles = Article.find_where(:all, :include => :author) do |article, author|
      article.title  =~ "%#{params['title']}%"
      article.body   =~ "%#{params['body']}%"
      author.name    == params['author']
    end
    assert_equal 1, articles.length

    params = { 'title' => nil, 'body' => nil, 'author' => nil }

    articles = Article.find_where(:all, :include => :author) do |article, author|
      article.title  =~ "%#{params['title']}%"
      article.body   =~ "%#{params['body']}%"
      author.name    == params['author']
    end
    assert_equal Article.find_where(:all).length, articles.length
  end

  def test_conditions_from_params_or_example
    params = { 'term' => 'package', 'author' => 'Fab' }

    articles = Article.find_where(:all, :include => :author) do |article, author|
      unless params['term'].nil?
        article.any do
          title  =~ "%#{params['term']}%"
          body   =~ "%#{params['term']}%"
        end
      end
      author.name == params['author']
    end

    assert_equal 1, articles.length
  end
  
  def test_nil_value_in_hash_conditions
    assert_equal "id IS NULL", {:id => nil}.to_sql
  end

  def test_create_clause
    cond = EZ::Where::Condition.new :my_table
    cond.create_clause(:foo, :=~, '%bar%')
    cond.create_clause(:biz, '==', 'baz')
    cond.create_clause(:case, :==, 'insensitive', true)
    expected = ["my_table.foo LIKE ? AND my_table.biz = ? AND UPPER(my_table.case) = ?", "%bar%", "baz", "INSENSITIVE"]
    assert_equal expected, cond.to_sql
  end

  def test_with_conditional_clauses
    fi_facility_id = 1
    fi_client_id = 2
    fi_case_manager_id = 3
    fi_accepted = true
    fi_pltype = nil

    expected = ["placements.facility_id = ? AND placements.client_id = ? AND placements.case_manager_id = ? AND placements.accepted = ?", 1, 2, 3, true]

    cond = EZ::Where::Condition.new :placements
    cond.clause(:facility_id) == fi_facility_id
    cond.clause(:client_id) == fi_client_id
    cond.clause(:case_manager_id) == fi_case_manager_id
    cond.clause(:accepted) == fi_accepted
    cond.clause(:pltype) == fi_pltype
    assert_equal expected, cond.to_sql

    # note: because of the lexical variable scope for block vars, you explicitly should have them set (nil is fine) outside the block
    # or else the block can't access them and gives 'undefined local variable or method'
    cond = EZ::Where::Condition.new :table_name => :placements do
      facility_id == fi_facility_id
      client_id == fi_client_id
      case_manager_id == fi_case_manager_id
      accepted == fi_accepted
      pltype == fi_pltype
    end
    assert_equal expected, cond.to_sql
  end

  def test_create_clause_from_map
    params = { :name => 'test', :price => 20, :postcode => 'BC234' }

    map = { :price => :>, :postcode => :=~ }
    map.default = :==

    cond = EZ::Where::Condition.new :my_table
    params.sort { |a, b| a.to_s <=> b.to_s }.each do |k,v|
      cond.create_clause(k, map[k], v)
    end
    expected = ["my_table.name = ? AND my_table.postcode LIKE ? AND my_table.price > ?", "test", "BC234", 20]
    assert_equal expected, cond.to_sql
  end

  def test_multi_clause
    expected = ["(my_table.title LIKE ? OR my_table.subtitle LIKE ? OR my_table.body LIKE ? OR my_table.footnotes LIKE ? OR my_table.keywords LIKE ?)", "%package%", "%package%", "%package%", "%package%", "%package%"]

    multi = EZ::Where::MultiClause.new([:title, :subtitle, :body, :footnotes, :keywords], :my_table)
    multi =~ '%package%'
    assert_equal expected, multi.to_sql

    cond = EZ::Where::Condition.new :my_table
    cond.any_of(:title, :subtitle, :body, :footnotes, :keywords) =~ '%package%'

    assert_equal expected, cond.to_sql

    cond = EZ::Where::Condition.new :my_table
    cond.any_of(:title, :subtitle, :body, :footnotes, :keywords) =~ '%package%'
    cond.all_of(:active, :flagged) == true

    expected = ["(my_table.title LIKE ? OR my_table.subtitle LIKE ? OR my_table.body LIKE ? OR my_table.footnotes LIKE ? OR my_table.keywords LIKE ?) AND (my_table.active = ? AND my_table.flagged = ?)", "%package%", "%package%", "%package%", "%package%", "%package%", true, true]
    assert_equal expected, cond.to_sql

    expected = ["(my_table.title LIKE ? OR my_table.subtitle LIKE ? OR my_table.body LIKE ? OR my_table.footnotes LIKE ? OR my_table.keywords LIKE ?) OR (my_table.active = ? AND my_table.flagged = ?)", "%package%", "%package%", "%package%", "%package%", "%package%", true, true]
    assert_equal expected, cond.to_sql(:or)
  end

  def test_multi_clause_ez_where
    articles = Article.find_where(:all) do |article|
      article.any_of(:title, :body) =~ '%package%'
      article.all_of(:title, :body) =~ '%the%'
    end
    assert_equal 1, articles.length
  end

  def test_sql_in_statement_and_any_of_all_of
    cond = EZ::Where::Condition.new :my_table
    cond.foo === ['bar', 'baz', 'buzz']
    cond.any_of(:created_by, :updated_by, :reviewed_by) == 2
    cond.all_of(:active, :flagged) == true
    cond.comments_count <=> [10, 15]
    expected = ["my_table.foo IN (?) AND (my_table.created_by = ? OR my_table.updated_by = ? OR my_table.reviewed_by = ?) AND (my_table.active = ? AND my_table.flagged = ?) AND (my_table.comments_count BETWEEN ? AND ?)", ["bar", "baz", "buzz"], 2, 2, 2, true, true, 10, 15]
    assert_equal expected, cond.to_sql
  end

  def test_case_insensitive_conditions
    cond = EZ::Where::Condition.new :table_name => :my_table, :inner => :or
    cond.name.nocase =~ '%fab%'
    cond.name.upcase =~ '%fab%' # also: downcase ...yeah yeah...
    cond.name.case_insensitive == 'foo'
    expected = ["UPPER(my_table.name) LIKE ? OR UPPER(my_table.name) LIKE ? OR UPPER(my_table.name) = ?", "%FAB%", "%FAB%", "FOO"]
    assert_equal expected, cond.to_sql

    cond = EZ::Where::Condition.new :my_table do
      foo.nocase == 'bar'
    end
    expected = ["UPPER(my_table.foo) = ?", "BAR"]
    assert_equal expected, cond.to_sql
  end

  def test_case_insensitive_multi_clause
    cond = EZ::Where::Condition.new :my_table
    cond.any_of(:title, :subtitle, :body, :footnotes, :keywords).nocase =~ '%package%'
    expected = ["(UPPER(my_table.title) LIKE ? OR UPPER(my_table.subtitle) LIKE ? OR UPPER(my_table.body) LIKE ? OR UPPER(my_table.footnotes) LIKE ? OR UPPER(my_table.keywords) LIKE ?)", "%PACKAGE%", "%PACKAGE%", "%PACKAGE%", "%PACKAGE%", "%PACKAGE%"]
    assert_equal expected, cond.to_sql
  end

  def test_case_insensitive_utf
    cond = EZ::Where::Condition.new :my_table
    cond.any_of(:title, :subtitle).nocase =~ '%zażółć%'
    expected = ["(UPPER(my_table.title) LIKE ? OR UPPER(my_table.subtitle) LIKE ?)", "%ZAŻÓŁĆ%", "%ZAŻÓŁĆ%"]
    assert_equal expected, cond.to_sql
  end
  
  def test_handling_of_empty_clause_values
    clause = EZ::Where::Clause.new(:name)
    clause == nil
    assert clause.empty?

    clause = EZ::Where::Clause.new(:name)
    clause == ''
    assert clause.empty?

    clause = EZ::Where::Clause.new(:name)
    clause =~ '%'
    assert clause.empty?

    clause = EZ::Where::Clause.new(:name)
    clause =~ '%%'
    assert clause.empty?

    clause = EZ::Where::Clause.new(:value)
    clause == false
    assert !clause.empty? # NOT empty

    clause = EZ::Where::SqlClause.new('')
    assert clause.empty?

    clause = EZ::Where::SqlClause.new(nil)
    assert clause.empty?

    clause = EZ::Where::ArrayClause.new(['name = ?', ''])
    assert clause.empty?

    clause = EZ::Where::ArrayClause.new(['name = ?', nil])
    assert clause.empty?

    clause = EZ::Where::ArrayClause.new(['id = 1'])
    assert !clause.empty? # NOT empty

    clause = EZ::Where::ArrayClause.new(['name = ?', false])
    assert !clause.empty? # NOT empty

    multi = EZ::Where::MultiClause.new([:title, :subtitle, :body, :footnotes, :keywords], :my_table)
    multi == nil
    assert multi.empty?

    multi = EZ::Where::MultiClause.new([:title, :subtitle, :body, :footnotes, :keywords], :my_table)
    multi =~ '%%'
    assert multi.empty?

    multi = EZ::Where::MultiClause.new([:title, :subtitle, :body, :footnotes, :keywords], :my_table)
    multi == false
    assert !multi.empty? # NOT empty
  end

  def test_empty_clause_values_in_complex_block
    cond = EZ::Where::Condition.new :my_table do
      any { name == nil; name =~ '%' }
      all { occupation == nil; country == '' }
    end
    cond << ['country = ?', '']
    cond << ''
    cond << false
    assert_nil cond.to_sql
  end

  def test_plus_operator_as_and_composition
    cond_a = EZ::Where::Condition.new(:my_table) { foo == 'bar' }
    cond_b = EZ::Where::Condition.new(:my_table) { biz == 'buzz' }
    cond_c = EZ::Where::Condition.new(:my_table) { name == 'new' }
    new_cond = cond_a + cond_b
    expected = ["(my_table.foo = ?) AND (my_table.biz = ?)", "bar", "buzz"]
    assert_equal expected, new_cond.to_sql
    new_cond = cond_a + cond_b + ['baz = ?', 'fizz']
    expected = ["((my_table.foo = ?) AND (my_table.biz = ?)) AND (baz = ?)", "bar", "buzz", "fizz"]
    assert_equal expected, new_cond.to_sql
    expected = ["((my_table.foo = ?) AND (my_table.biz = ?)) AND (my_table.name = ?)", "bar", "buzz", "new"]
    new_cond = (cond_a + cond_b + cond_c)
    assert_equal expected, new_cond.to_sql
  end

  def test_minus_operator_as_and_not_composition
    cond_a = EZ::Where::Condition.new(:my_table) { foo == 'bar' }
    cond_b = EZ::Where::Condition.new(:my_table) { biz == 'buzz' }
    cond_c = EZ::Where::Condition.new(:my_table) { name == 'new' }
    new_cond = cond_a - cond_b
    expected = ["(my_table.foo = ?) AND NOT (my_table.biz = ?)", "bar", "buzz"]
    assert_equal expected, new_cond.to_sql
    new_cond = cond_a - (cond_b + cond_c)
    expected = ["(my_table.foo = ?) AND NOT ((my_table.biz = ?) AND (my_table.name = ?))", "bar", "buzz", "new"]
    assert_equal expected, new_cond.to_sql
  end

  def test_pipe_operator_as_or_composition
    cond_a = EZ::Where::Condition.new(:my_table) { foo == 'bar' }
    cond_b = EZ::Where::Condition.new(:my_table) { biz == 'buzz' }
    cond_c = EZ::Where::Condition.new(:my_table) { name == 'new' }
    cond_d = EZ::Where::Condition.new(:my_table) { country == 'usa' }
    new_cond = ((cond_a | cond_b | cond_c) | cond_d)
    expected = ["(((my_table.foo = ?) OR (my_table.biz = ?)) OR (my_table.name = ?)) OR (my_table.country = ?)", "bar", "buzz", "new", "usa"]
    assert_equal expected, new_cond.to_sql
  end

  def test_composition
    new_cond = (c(:my_table) { foo == 'bar' } + c(:other_table) { biz == 'baz' }) | c{ number === [1, 2, 3] }
    expected = ["((my_table.foo = ?) AND (other_table.biz = ?)) OR (number IN (?))", "bar", "baz", [1, 2, 3]]
    assert_equal expected, new_cond.to_sql
    new_cond = ((c + 'age > 20' - ['user_id IN (?)', 1..5]) | ['name = ?', 'fab'])
    expected = ["((age > 20) AND NOT (user_id IN (?))) OR (name = ?)", 1..5, "fab"]
    assert_equal expected, new_cond.to_sql
  end

  def test_simple_example
    cond = EZ::Where::Condition.new # you could use c but it's a bit short here
    cond += c { name == 'fab' } + c { login =~ 'loob%' } # AND - AND
    expected = ["((name = ?) AND (login LIKE ?))", "fab", "loob%"]
    assert_equal expected, cond.to_sql
    cond -= c { age < 20 } | c { login_count < 10 }    # AND NOT - OR
    expected = ["(((name = ?) AND (login LIKE ?))) AND NOT ((age < ?) OR (login_count < ?))", "fab", "loob%", 20, 10]
    assert_equal expected, cond.to_sql
    cond |= c { login == 'admin' }                # OR - 
    expected = ["((((name = ?) AND (login LIKE ?))) AND NOT ((age < ?) OR (login_count < ?))) OR (login = ?)", "fab", "loob%", 20, 10, "admin"]
    assert_equal expected, cond.to_sql
    cond += { :color => 'red' }
    expected = ["(((((name = ?) AND (login LIKE ?))) AND NOT ((age < ?) OR (login_count < ?))) OR (login = ?)) AND (color = ?)", "fab", "loob%", 20, 10, "admin", "red"]
    assert_equal expected, cond.to_sql
  end

  def test_composition_in_steps
    cond = c(:my_table) { combine c { name == 'fab' } | c { name =~ 'ez%' } }
    expected = ["((my_table.name = ?) OR (my_table.name LIKE ?))", "fab", "ez%"]
    assert_equal expected, cond.to_sql
    cond += c(:other_table) { gemz === (1..5) }
    expected = ["(((my_table.name = ?) OR (my_table.name LIKE ?))) AND (other_table.gemz IN (?))", "fab", "ez%", [1, 2, 3, 4, 5]]
    assert_equal expected, cond.to_sql
    cond -= 'age > 20'
    expected = ["((((my_table.name = ?) OR (my_table.name LIKE ?))) AND (other_table.gemz IN (?))) AND NOT age > 20", "fab", "ez%", [1, 2, 3, 4, 5]]
    assert_equal expected, cond.to_sql    
    cond |= c(:other_table) { login_count <=> (1..5) }
    expected = ["(((((my_table.name = ?) OR (my_table.name LIKE ?))) AND (other_table.gemz IN (?))) AND NOT age > 20) OR (other_table.login_count BETWEEN ? AND ?)", "fab", "ez%", [1, 2, 3, 4, 5], 1, 5]
    assert_equal expected, cond.to_sql
  end

  def test_complex_operator_composition
    cond_a = c(:my_table) { foo == 'bar' }
    cond_b = c(:my_table) { biz == 'buzz' }
    cond_c = c(:my_table) { name == 'new' }
    cond_d = c(:my_table) { country == 'belgium' }
    new_cond = (((cond_a | cond_b) - (cond_c + cond_d)) + 'age > 20') | ['user_name = ?', 'fab']
    expected = ["((((my_table.foo = ?) OR (my_table.biz = ?)) AND NOT ((my_table.name = ?) AND (my_table.country = ?))) AND age > 20) OR (user_name = ?)", "bar", "buzz", "new", "belgium", "fab"]
    assert_equal expected, new_cond.to_sql
  end

  def test_cc_with_multiple_statements
    a = c { foo == 'bar' }
    b = c { baz =~ '%qux%' }
    c = c { age > 20 }
    d = c { gemz === (1..5) }
    expected = ["((foo = ?) AND (baz LIKE ?)) OR ((age > ?) AND NOT (gemz IN (?)))", "bar", "%qux%", 20, [1, 2, 3, 4, 5]]
    assert_equal expected, (a + b | c - d).to_sql
  end

  def test_create_condition_and_respect_table_name
    cond = c(:my_table) { combine c { baz =~ '%qux%' } + c { gemz === (1..5) } | c(:other_table) { foo == 'bar' } }
    expected = ["(((my_table.baz LIKE ?) AND (my_table.gemz IN (?))) OR (other_table.foo = ?))", "%qux%", [1, 2, 3, 4, 5], "bar"]
    assert_equal expected, cond.to_sql
    cond = c(:my_table) { combine c { baz =~ '%qux%' } - (c { foo == 'bar' } | 'age < 20') + c(:other_table) { combine c { name === %w{ fab ezra } } | c { login == 'admin' } } }
    expected = ["(((my_table.baz LIKE ?) AND NOT ((my_table.foo = ?) OR age < 20)) AND (((other_table.name IN (?)) OR (other_table.login = ?))))", "%qux%", "bar", ["fab", "ezra"], 'admin']
    assert_equal expected, cond.to_sql
  end

  def test_cc_with_literal_hashes
    cond = (c + { :name => 'fab', :country => 'BE' } | { :name => 'ezra', :country => 'US' }) + { :foo => 'bar' }
    match = /\(\((country|name) = \? AND (country|name) = \?\) OR \((country|name) = \? AND (country|name) = \?\)\) AND \(foo = \?\)/
    assert_match match, cond.to_sql.first
  end

  def test_cc_with_statements_inline
    cond = c { foo == 'bar'; baz =~ '%buzz%' } | ((c { name == 'fab' } + 'age > 20') | 'age = 25')
    expected = ["(foo = ? AND baz LIKE ?) OR (((name = ?) AND age > 20) OR age = 25)", "bar", "%buzz%", "fab"]
    assert_equal expected, cond.to_sql
  end
  
  def test_cc_with_statements_inline_contrived_example
    cond = c(:my_table) { foo == 'bar'; baz =~ '%buzz%'; any { name == 'fab'; name == 'ezra' } } + 'age > 20' - { :color => 'red', :number => 'five' }
    expected = /\(\(my_table\.foo = \? AND my_table\.baz LIKE \? AND \(my_table\.name = \? OR my_table\.name = \?\)\) AND age > 20\) AND NOT \((number = \? AND color = \?|color = \? AND number = \?)\)/
    assert_match expected, cond.to_sql.first
  end

  def test_within_find_where_block
    # notice how <model>.c is called to scope to the right table
    # generates: WHERE ((((articles.body LIKE '%Rail%') AND NOT (articles.body LIKE '%Railroad%'))) AND (((authors.name = 'Ezra') OR (authors.name = 'Fab'))))
    articles = Article.find_where(:all, :include => :author) do |article, author|
     article << (article.c { body =~ "%Rail%" } - article.c { body =~ "%Railroad%" }) # append (a AND NOT b)
     author  << (author.c { name == 'Ezra' } | author.c { name == 'Fab' })        # append (c OR d)
    end    
    assert_equal 2, articles.length
  end

  def test_within_find_where_block_alt_syntax
    # notice how <model>.c is called to scope to the right table
    # generates: WHERE (((((articles.body LIKE '%Rail%') AND NOT (articles.body LIKE '%Railroad%')) AND ((authors.name = 'Ezra') OR (authors.name = 'Fab')))))
    articles = Article.find_where(:all, :include => :author) do |article, author|
     article.combine((article.c { body =~ "%Rail%" } - article.c { body =~ "%Railroad%" }) + (author.c { name == 'Ezra' } | author.c { name == 'Fab' })) # (a AND NOT b) AND (c OR d)
    end    
    assert_equal 2, articles.length
  end

  def test_to_condition
    assert_equal ['age > 20'], 'age > 20'.to_c.to_sql
    assert_equal ['(name = ?)', 'fab'], ['name = ?', 'fab'].to_c.to_sql
    assert_equal ["(color = ?)", "red"], { :color => 'red' }.to_c.to_sql
  end

  def test_use_to_condition
    cond = ('age > 20'.to_c | c { name =~ 'fab%' }) + { :color => 'red' }
    expected = ["((age > 20) OR (name LIKE ?)) AND (color = ?)", "fab%", "red"]
    assert_equal expected, cond.to_sql
  end

  def test_nested_include_conditions
    # any articles written by or commented on by Fab, using subcondition
    articles = Article.find_where(:all, :include => [:author, { :comments => :user }]) do |article, author, comment|
      article.author_id == 2
      author.name == 'Ezra'
      comment.body =~ '%Lorem%'
    end
    assert articles.length == 1
  end
  
  def test_use_class_const_to_deduce_table_name
    assert_equal ["articles.title LIKE ?", "Lorem%"], (c(Article) { title =~ 'Lorem%' }).to_sql
    assert_equal ["authors.name = ?", "foo"], (c(Author) { name == 'foo' }).to_sql
    
    assert_equal ["articles.title LIKE ?", "Lorem%"], Article.c { title =~ 'Lorem%' }.to_sql
    assert_equal ["authors.name = ?", "foo"], Author.c { name == 'foo' }.to_sql
  end
  
  def test_use_condition_directly_as_conditions
    articles = Article.find(:all, :conditions => Article.c { author_id == 2 })
    assert_equal 1, articles.length    
  end
  
  def test_composition
    assert_equal nil, Article.composition(:base).to_sql
    assert_equal nil, Article.composition(:default).to_sql
    expected = ["articles.active = ? AND articles.hidden = ? AND articles.deactivated_at IS NULL", true, false]
    assert_equal expected, Article.composition(:active).to_sql   
    expected = ["(articles.active = ? AND articles.hidden = ? AND articles.deactivated_at IS NULL) AND ((articles.publish_at IS NULL AND articles.unpublish_at IS NULL) OR ((articles.publish_at <= ?) AND ((articles.unpublish_at > ?) OR (articles.unpublish_at IS NULL))))", true, false, Time.new.beginning_of_day, Time.new.beginning_of_day]    
    assert_equal expected, Article.composition(:published, Time.new.beginning_of_day).to_sql
  end
  
  def test_arbitrary_object_with_to_cond
    cond = EZ::Where::Condition.new
    cond.append SampleToCond # class method
    cond.append SampleToCond.new # instance method
    expected = ["(sample_to_conds.active = ?) AND (sample_to_conds.hidden = ?)", true, false]
    assert_equal expected, cond.to_sql
    
    cond = EZ::Where::Condition.new
    cond += 'number > 20'.to_c + SampleToCond
    cond -= SampleToCond.new
    expected = ["(((number > 20) AND (sample_to_conds.active = ?))) AND NOT (sample_to_conds.hidden = ?)", true, false]
    assert_equal expected, cond.to_sql
  end
  
  def test_activerecord_to_cond
    cond = Article.find(2).to_c
    assert_equal ["(articles.id = ?)", 2], cond.to_sql
    cond = Article.find(2).to_cond
    assert_equal ["articles.id = ?", 2], cond.to_sql
    
    assert_nil Article.to_c.to_sql # no STI so nil
    assert_nil Article.to_cond.to_sql # no STI so nil  
    
    article = Article.new { |art| art.title = 'lorem ipsum' }      
    cond = article.to_c | Article.c { user_id == 2 } # note the schema.rb default values...
    expected = ["(articles.title = ? AND articles.hidden = ? AND articles.active = ?) OR (articles.user_id = ?)", "lorem ipsum", 0, 1, 2]
    assert_equal expected, cond.to_sql
  end
  
  def test_within_time_delta  
    cond = Article.c { created_at.within_time_delta(2006) }
    expected = "[\"(articles.created_at BETWEEN ? AND ?)\", #{Time.local(2006)}, #{Time.local(2007)}]"
    assert_equal expected, cond.to_sql.inspect
    cond = Article.c { created_at.within_time_delta(2006, 6) }
    expected = "[\"(articles.created_at BETWEEN ? AND ?)\", #{Time.local(2006, 6, 1)}, #{Time.local(2006, 7, 1)}]"
    assert_equal expected, cond.to_sql.inspect
    cond = Article.c { created_at.within_time_delta(2006, 6, 15) }
    expected = "[\"(articles.created_at BETWEEN ? AND ?)\", #{Time.local(2006, 6, 15)}, #{Time.local(2006, 6, 16)}]"
    assert_equal expected, cond.to_sql.inspect
    cond = Article.c { created_at.within_time_delta(Time.utc(2006, 6, 15)) }
    assert_equal expected, cond.to_sql.inspect
  end

  def test_day_range
    cond = Article.c
    cond.created_at.days_ago(7, Time.utc(2006, 6, 15))
    expected = "[\"(articles.created_at BETWEEN ? AND ?)\", Thu Jun 08 00:00:00 UTC 2006, Thu Jun 15 00:00:00 UTC 2006]"
    assert_equal expected, cond.to_sql.inspect
    cond = Article.c { created_at.days_ago(3..5, Time.utc(2006, 6, 15)) }
    expected = "[\"(articles.created_at BETWEEN ? AND ?)\", Sat Jun 10 00:00:00 UTC 2006, Mon Jun 12 00:00:00 UTC 2006]"
    assert_equal expected, cond.to_sql.inspect
    cond = Article.c { created_at.days_ago(30, Time.utc(2006, 7, 1)) }
    expected = "[\"(articles.created_at BETWEEN ? AND ?)\", Thu Jun 01 00:00:00 UTC 2006, Sat Jul 01 00:00:00 UTC 2006]"
    assert_equal expected, cond.to_sql.inspect
    cond = Article.c(:inner => :or) { created_at.days_ago(7, Time.utc(2006, 6, 15)); updated_at.days_ago(7, Time.utc(2006, 6, 15)) } + Article.c { user_id == 2 }
    expected = "[\"((articles.created_at BETWEEN ? AND ?) OR (articles.updated_at BETWEEN ? AND ?)) AND (articles.user_id = ?)\", Thu Jun 08 00:00:00 UTC 2006, Thu Jun 15 00:00:00 UTC 2006, Thu Jun 08 00:00:00 UTC 2006, Thu Jun 15 00:00:00 UTC 2006, 2]"
    assert_equal expected, cond.to_sql.inspect
  end
  
  # new and easy syntax - recommended
  
  def test_arity_based_block_yield
    cond = EZ::Where::Condition.new(:my_table) { column == 'foo' }
    assert_equal ["my_table.column = ?", "foo"], cond.to_sql
    
    cond = EZ::Where::Condition.new(:my_table) { |table| table.column == 'foo' }
    assert_equal ["my_table.column = ?", "foo"], cond.to_sql
    
    cond = EZ::Where::Condition.new(:my_table) do |table| 
      table.column == 'foo'
      table << 'user_id NOT IN (1, 2, 3)'
      table << { :color => 'red' }
    end
    assert_equal ["my_table.column = ? AND user_id NOT IN (1, 2, 3) AND (color = ?)", "foo", "red"], cond.to_sql
  end
  
  
  def test_and_or_not_syntax
    cond = c { name == 'Fab' }.and(c.title =~ 'Lorem%').not( (c.comments_count == 1) | (c.comments_count == :null) )
    expected = ["name = ? AND (title LIKE ?) AND NOT ((comments_count = ?) OR (comments_count IS NULL))", "Fab", "Lorem%", 1]
    assert_equal expected, cond.to_sql
    
    cond = c { foo == 'bar' }.and {
      c { biz == 'baz' } | c { biz == :null }
    }.not(c.flip == 'flop')
      
    expected = ["foo = ? AND ((biz = ?) OR (biz IS NULL)) AND NOT (flip = ?)", "bar", "baz", "flop"]
    assert_equal expected, cond.to_sql
    
    cond = c { foo == 'bar' }.and { c { biz == 'baz' }.or c { biz == :null } }.not(c.flip == 'flop')
    expected = ["foo = ? AND (biz = ? OR (biz IS NULL)) AND NOT (flip = ?)", "bar", "baz", "flop"]
    assert_equal expected, cond.to_sql
  end
  
  def test_find_where_options_with_and_or_not_syntax
    options = Article.find_where_options do |article|
      article.title == 'Rails'  
      # notice the .c. inbetween to create a copy instead of appending directly  
      article.not( (article.c.comments_count == 0) | (article.c.comments_count == :null) )
      article.and( (article.author.c.name == 'Ezra') | (article.author.c.name == 'Fab') )
    end
    expected = {:conditions=>["(articles.title = ? AND NOT ((articles.comments_count = ?) OR (articles.comments_count IS NULL)) AND ((authors.name = ?) OR (authors.name = ?)))", "Rails", 0, "Ezra", "Fab"], :include=>{:author=>{}}}
    assert_equal expected, options
  end
  
  def test_find_where_options 
    options = Article.find_where_options(:limit => 5, :order => 'articles.title') do |article|
     article.author.name == 'Ezra'
    end
    expected = {:order=>"articles.title", :limit=>5, :include=>{:author=>{}}, :conditions=>["(authors.name = ?)", "Ezra"]}
    assert_equal expected, options
  end
  
  def test_simplified_associations_standalone
    assert_equal ["users.name = ?", "Fab"], (c(:comments).user.name == 'Fab').to_sql
    assert_equal ["(users.name = ?)", "Ezra"], c(:article) { |art| art.comments.user.name == 'Ezra' }.to_sql
    assert_equal ["(authors.name = ?)", "Fab"], Article.c { |article| article.author.name == 'Fab' }.to_sql
    
    cond = (c(:article).title =~ 'Lorem%') | (c(:article).comments.user.name =~ 'F%')
    expected = ["(articles.title LIKE ?) OR (users.name LIKE ?)", "Lorem%", "F%"]
    assert_equal expected, cond.to_sql
    
    cond = c(:article) { title =~ 'Lorem%' } | c(:article).comments.user { name =~ 'F%' }
    expected = ["(articles.title LIKE ?) OR (users.name LIKE ?)", "Lorem%", "F%"]
    assert_equal expected, cond.to_sql
  end
  
  def test_simplified_associations_syntax
    options = Article.find_where_options do |article|
      article.author.name == 'Ezra'
    end
    expected = {:include=>{:author=>{}}, :conditions=>["(authors.name = ?)", "Ezra"]}
    assert_equal expected, options
    
    options = Article.find_where_options do |article|
      article.comments.user.name == 'Ezra'
    end
    expected = {:include=>{:comments=>{:user=>{}}}, :conditions=>["(users.name = ?)", "Ezra"]}
    assert_equal expected, options
    
    options = Author.find_where_options do |author|
      author.articles.title =~ 'Who%'
    end
    expected = {:include=>{:articles=>{}}, :conditions=>["(articles.title LIKE ?)", "Who%"]}
    assert_equal expected, options
    
    options = Article.find_where_options do |article|
      article.title =~ 'Who%'
      article.comments.body =~ "Lorem%"
      article.comments.user.name == 'Ezra'
    end
    expected = {:include=>{:comments=>{:user=>{}}}, :conditions=> ["(articles.title LIKE ? AND (comments.body LIKE ?) AND (users.name = ?))", "Who%", "Lorem%", "Ezra"]}
    assert_equal expected, options
  end
  
  def test_simplified_associations_syntax_with_block
    options = Article.find_where_options do |article|
      article.comments do |comm|
        comm.body =~ "Lorem%"
        comm.user.name == 'Fab'
      end
    end
    expected = {:include=>{:comments=>{:user=>{}}}, :conditions=>["((comments.body LIKE ? AND (users.name = ?)))", "Lorem%", "Fab"]}
    assert_equal expected, options
 
    options = Article.find_where_options do |article|
      article.author.any { |author| author.name == 'Ezra'; author.name == 'Fab' }
    end
    expected = {:include=>{:author=>{}}, :conditions=>["(authors.name = ? OR authors.name = ?)", "Ezra", "Fab"]}
    assert_equal expected, options
 
    options = Article.find_where_options do |article|
      article.comments :inner => :or do |comm|
        comm.user.name == 'Fab'
        comm.user.name == 'Ezra'
      end
    end
    expected = {:include=>{:comments=>{:user=>{}}}, :conditions=>["(((users.name = ?) OR (users.name = ?)))", "Fab", "Ezra"]}
    assert_equal expected, options
  end
  
  def test_simplified_associations_syntax_with_any_and_all
    options = Article.find_where_options do |article|
      article.comments(:outer => :or) do |comm|
        comm.all do |co|         
          co.body =~ "Lorem%"
          co.user.name == :null       
        end
        comm.any do |co|
          co.user.name == 'Fab'
          co.user.name == 'Ezra'
        end
        
      end
    end
    expected = {:include=>{:comments=>{}}, :conditions=> ["(((comments.body LIKE ? AND (users.name IS NULL)) OR ((users.name = ?) OR (users.name = ?))))", "Lorem%", "Fab", "Ezra"]} 
    assert_equal expected, options 
  end
  
  def test_direct_object_associations_syntax
    options = Article.find_where_options do |article|
      article.comments.user == User.find(1)
    end
    expected = {:include=>{:comments=>{:user=>{}}}, :conditions=>["(comments.user_id = ?)", 1]}
    assert_equal expected, options
    
    options = Article.find_where_options do |article|
      article.comments.user === User.find(1, 2)
    end
    expected = {:include=>{:comments=>{:user=>{}}}, :conditions=>["(((comments.user_id IN (?))))", [1, 2]]}
    assert_equal expected, options
  end
  
  def test_combine_syntax
    options = Article.find_where_options do |article|
      article.title == 'Rails'    
      article.and article.comments.c { title == 'A%' } | article.comments.c { title == 'B%' }
    end
    expected = ["(articles.title = ? AND ((comments.title = ?) OR (comments.title = ?)))", "Rails", "A%", "B%"]
    assert_equal expected, options[:conditions]
    
    options = Article.find_where_options do |article|
      article.comments.user.name == 'Fab'
      article.and( (article.c.title =~ 'A%') | (article.c.title =~ 'B%') )
      article.comments.any do 
        body =~ 'Lorem%'
        body =~ 'Ipsum%'
      end
    end
    expected = {:include=>{:comments=>{:user=>{}}}, :conditions=>["((users.name = ?) AND ((articles.title LIKE ?) OR (articles.title LIKE ?)) AND (comments.body LIKE ? OR comments.body LIKE ?))", "Fab", "A%", "B%", "Lorem%", "Ipsum%"]}
    assert_equal expected, options
  end
  
  def test_order_option
    options = Article.find_where_options do |article|
      article.title.order! :asc
      article.author.name.order! :desc
      article.comments.user.name.order!
    end
    expected = {:order=>"articles.title ASC, authors.name DESC, users.name ASC",:conditions=>nil, :include=>{:author=>{}, :comments=>{:user=>{}}}}
    assert_equal expected, options
    
    options = Article.find_where_options(:order => 'articles.title') do |article|
      article.author.name.order! :desc
      article.comments.title.order!
      article.comments.user.name.order!
    end
    expected = {:order=>"articles.title, authors.name DESC, comments.title ASC, users.name ASC",:conditions=>nil, :include=>{:author=>{}, :comments=>{:user=>{}}}}
    assert_equal expected, options
    
    articles = Article.find_where(:all) do |article|
      article.title.order! :desc
      article.author.name.order! :desc
      article.comments.user.name.order!
    end
    assert_equal 2, articles.first.id
  end
  
end
