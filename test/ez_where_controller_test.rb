require File.dirname(__FILE__) + '/test_helper'
require 'action_controller/test_process'

ActionController::Base.send :include, EZ::Where

ActionController::Routing::Routes.draw do |map|
  map.connect ':controller/:action/:id'
end

# The base class for testing.
class MockController < ActionController::Base
  def rescue_action(e) raise e end; 
  
  def find_where
    @articles_a = Article.find_where(:all, :include => :author) do |article, author|
      article.title =~ params[:title_like]
    end
    @articles_b = Article.find_where(:all, :include => :author) do |article, author|
      article.title =~ params[:title_like]
      author.id == session[:user_id]
    end
    render :nothing => true
  end
  
  def create_condition
     @condition = (c(:users){ login =~ params[:login] } | c(:users) { email == params[:email] }).to_sql
     render :nothing => true   
  end
  
  def complex_conditions
    cond = c { name == 'fab' } + c { login =~ 'loob%' }
    cond -= c { age < 20 } | c { login_count < 10 }
    cond |= c { login == params[:login] }
    cond += { :color => 'red' }
    @condition_a = cond.to_sql   
    cond = ((c + 'age > 20' - ['user_id IN (?)', 1..5]) | ['login = ?', params[:login] ])
    @condition_b = cond.to_sql
    cond = c(:my_table) { foo == 'bar'; baz =~ '%buzz%'; any { login == params[:login]; name == 'ezra' } } + 'age > 20' - { :color => 'red', :number => 'five' }
    @condition_c = cond.to_sql
    render :nothing => true 
  end
  
end

class EzWhereWithinControllerTest < Test::Unit::TestCase
  
  fixtures :articles, :authors, :comments
  
  def setup
    @request    = ActionController::TestRequest.new
    @response   = ActionController::TestResponse.new
    @controller = MockController.new
  end
  
  def test_find_where
    get :find_where, { :title_like => 'Wh%' }, { :user_id => 1 }
    assert_response :success
    assert_equal 2, assigns(:articles_a).length
    assert_equal 1, assigns(:articles_b).length    
  end
  
  def test_create_condition
    get :create_condition, :login => 'foo', :email => 'foo@bar.com'
    assert_response :success
    assert_equal ["(users.login LIKE ?) OR (users.email = ?)", "foo", "foo@bar.com"], assigns(:condition)    
  end
  
  def test_complex_condition
    get :complex_conditions, :login => 'foo'
    assert_response :success
    expected = ["((((name = ?) AND (login LIKE ?)) AND NOT ((age < ?) OR (login_count < ?))) OR (login = ?)) AND (color = ?)","fab", "loob%", 20, 10, "foo", "red"]
    assert_equal expected, assigns(:condition_a) 
    expected = ["((age > 20) AND NOT (user_id IN (?))) OR (login = ?)", 1..5, "foo"]
    assert_equal expected, assigns(:condition_b)
    expected = ["((my_table.foo = ? AND my_table.baz LIKE ? AND (my_table.login = ? OR my_table.name = ?)) AND age > 20) AND NOT (color = ? AND number = ?)", "bar", "%buzz%", "foo", "ezra", "red", "five"]
    assert_equal expected, assigns(:condition_c)         
  end
  
end