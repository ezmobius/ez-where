module EZ

  module Where
    # EZ::Condition plugin for generating the :conditions where clause
    # for ActiveRecord::Base.find. And an extension to ActiveRecord::Base
    # called AR::Base.find_where that takes a block and builds
    # the where clause dynamically for you.
    
    class AbstractClause
      
      attr_reader :test
      attr_accessor :outer
      attr_accessor :case_insensitive
      
      def to_sql; nil; end
      
      def case_insensitive
        @case_insensitive = true
        self
      end

      alias :downcase :case_insensitive
      alias :upcase :case_insensitive
      alias :nocase :case_insensitive
            
      def empty?
        true
      end
      
    end
    
    class Clause < AbstractClause
      # need this so that id doesn't call Object#id
      # left it open to add more methods that
      # conflict when I find them
      [:id, :type].each { |m| undef_method m }
      
      attr_reader :name, :test, :value
      
      attr_accessor :cond # NEW
      
      # Initialize a Clause object with the name of the
      # column.    
      def initialize(*args)
        @cond = args.shift if args.first.kind_of?(Condition)
        @table_prefix = ''
        @negate = false
        @case_insensitive = false
        case args.length
        when 0:
          raise 'Expected at least one parameter'
        when 1:
          @name = args.first.to_s
        when 2:
          @table_prefix = args[0].to_s + '.' unless args[0].to_s.empty? 
          @name = args[1].to_s
        when 3:
          @table_prefix = args[0].to_s + '.' unless args[0].to_s.empty? 
          @name = args[1].to_s
          @negate = args[2]
        end
        # append ! to negate the statement
        if @name[-1].chr == '!'
          @negate = true
          @name = @name.slice(0, @name.length - 1) 
        end
        # prefix with esc_ to avoid clashes with standard methods like 'alias'
        @name = @name.slice(4, @name.length) if @name =~ /^esc_.*/
      end
    
      # The == operator has been over-ridden here to
      # stand in for an exact match ["foo = ?", "bar"]
      def ==(other)
        @test = :equals
        @value = (other.kind_of?(Symbol) and other != :null) ? other.to_s : other
        return self.cond    
      end
    
      # The =~ operator has been over-ridden here to
      # stand in for the sql LIKE "%foobar%" clause.
      def =~(pattern)
        @test = :like
        @value = pattern
        return self.cond    
      end
      
      # The % operator has been over-ridden here to
      # stand in for the sql SOUNDS LIKE "%foobar%" clause.
      # This isn't always supported on all RDMSes.
      def %(string)
        @test = :soundex
        @value = string
        return self.cond    
      end
      
      # The spaceship <=> operator has been over-ridden here to
      # stand in for the sql ["BETWEEN ? AND ?", 1, 5] "%foobar%" clause.
      def <=>(range)
        @test = :between
        @value = range
        return self.cond    
      end
    
      # The === operator has been over-ridden here to
      # stand in for the sql ["IN (?)", [1,2,3]] clause.
      def ===(range)
        @test = :in
        @value = range
        return self.cond    
      end
    
      def within_time_delta(year_or_time, month = nil, day = nil)
        @test = :between
        year_or_time = year_or_time.to_time if year_or_time.respond_to?(:to_time)
        @value = year_or_time.respond_to?(:to_delta) ? year_or_time.to_delta : Time.delta(year_or_time, month, day)
        return self.cond    
      end
      
      def day_range(age_in_days = 7, now = Time.new)
        @test = :between
        if age_in_days.kind_of? Range
          @value = Range.new(now.ago(age_in_days.end.day), now.ago(age_in_days.begin.day))
        else
          @value = Range.new(now.ago(age_in_days.day), now)
        end
        return self.cond    
      end
      alias :days_ago :day_range
          
      def order!(direction = :asc)
        self.cond.base.order_by << "#{@table_prefix}#{self.name} #{direction.to_s.upcase}" if (self.cond && self.cond.base)
      end
         
      # switch on @test and build appropriate clause to 
      # match the operation.
      def to_sql
        return nil if empty?
        value = @value
        value = value.id if value.kind_of?(ActiveRecord::Base)
        case @test
          when :equals
            if value == :null
              @negate ? ["#{@table_prefix}#{@name} IS NOT NULL"] : ["#{@table_prefix}#{@name} IS NULL"] 
            else
              if @case_insensitive and value.respond_to?(:upcase)
                @negate ? ["UPPER(#{@table_prefix}#{@name}) != ?", value.upcase] : ["UPPER(#{@table_prefix}#{@name}) = ?", value.upcase] 
              else
                @negate ? ["#{@table_prefix}#{@name} != ?", value] : ["#{@table_prefix}#{@name} = ?", value] 
              end
            end 
          when :like
            if @value.kind_of?(Regexp)
              str = @value.inspect
              str = str[str.index('/') + 1, str.rindex('/') - 1]
              @negate ? ["#{@table_prefix}#{@name} NOT REGEXP ?", str] : ["#{@table_prefix}#{@name} REGEXP ?", str]           
            else
              if @case_insensitive and value.respond_to?(:upcase)
                @negate ? ["UPPER(#{@table_prefix}#{@name}) NOT LIKE ?", value.upcase] : ["UPPER(#{@table_prefix}#{@name}) LIKE ?", value.upcase]
              else
                @negate ? ["#{@table_prefix}#{@name} NOT LIKE ?", value] : ["#{@table_prefix}#{@name} LIKE ?", value]
              end
            end
          when :soundex
            ["#{@table_prefix}#{@name} SOUNDS LIKE ?", value]
          when :between
            @negate ? ["(#{@table_prefix}#{@name} NOT BETWEEN ? AND ?)", [value.first, value.last]] : ["(#{@table_prefix}#{@name} BETWEEN ? AND ?)", [value.first, value.last]] 
          when :in
            @negate ? ["#{@table_prefix}#{@name} NOT IN (?)", value.to_a] : ["#{@table_prefix}#{@name} IN (?)", value.to_a] 
          else
            ["#{@table_prefix}#{@name} #{@test} ?", value]
          end
      end
    
      # If a clause is empty it won't be added to the condition at all
      def empty?
        (@value.to_s.empty? or (@test == :like and @value.to_s =~ /^([%]+)$/))
      end
    
      # This method_missing takes care of setting
      # @test to any operator thats not covered 
      # above. And @value to the value
      def method_missing(name, *args)
        @test = name
        @value = args.first
        return self.cond    
      end
    end
    
    class ArrayClause < AbstractClause
      
      # wraps around an Array in ActiveRecord format ['column = ?', 2]
      
      def initialize(cond_array)
        @test = :array
        @cond_array = cond_array || []
      end
            
      def to_sql
        return nil if empty?
        query = (@cond_array.first =~ /^\([^\(\)]+\)$/) ? "#{@cond_array.first}" : "(#{@cond_array.first})"
        [query, values]
      end
   
      def values
        @cond_array[1..@cond_array.length].select { |value| !value.to_s.empty? }
      end
    
      def empty?
        return false if !@cond_array.empty? && @cond_array.first.to_s =~ /NULL/i
        (@cond_array.empty? || @cond_array.first.to_s.empty? || (@cond_array.first.to_s =~ /\?/ && values.empty?))
      end
      
    end
    
    class SqlClause < AbstractClause
      
      # wraps around a raw SQL string
      
      def initialize(sql)
        @test = :sql
        @sql = sql
      end
      
      def to_sql
        return nil if empty?
        [@sql]
      end
      
      def empty?
        @sql.to_s.empty?
      end
      
    end
    
    class MultiClause < AbstractClause
      
      # wraps around a multiple column clause
      
      [:==, :===, :=~].each { |m| undef_method m }
      
      def initialize(names, table_name = nil, inner = :or)
        @test = :multi 
        @operator = :==
        @value = nil
        @names, @table_name, @inner, = names, table_name, inner
      end
      
      def method_missing(operator, *args)
        if [:<, :>, :<=, :>=, :==, :===, :=~, :%, :<=>].include?(operator)
          @operator = operator
          @value = args.first
        end
        return self
      end
      
      def to_sql
        return nil if empty?
        cond = EZ::Where::Condition.new :table_name => @table_name, :inner => @inner, :parenthesis => true
        @names.each { |name| cond.create_clause(name, @operator, @value, @case_insensitive) }     
        return cond.to_sql
      end
      
      def empty?
        (@value.to_s.empty? or @names.empty? or @value.to_s =~ /^([%]+)$/)
      end
            
    end 
    
  end # EZ
      
end # Caboose    

class Time
  unless respond_to?(:to_delta) 
    def to_delta(delta_type = :day)
      case delta_type
        when :year then self.class.delta(year)
        when :month then self.class.delta(year, month)
        else self.class.delta(year, month, day)
      end
    end 
  end
  class << self
    unless respond_to?(:delta)
      def delta(year, month = nil, day = nil)
        from = Time.mktime(year, month || 1, day || 1)
        to   = from.next_year.beginning_of_year
        to   = from.end_of_month  unless month.blank?    
        to   = from + 1.day       unless day.blank?
        to   = to.tomorrow        unless month.blank? or day
        [from.midnight, to.midnight]
      end
    end
  end
end