class ActiveRecord::Base
  class << self
    alias :original_sanitize_sql :sanitize_sql   
    def sanitize_sql(condition)
      condition = condition.to_sql if EZ::Where::Condition === condition
      original_sanitize_sql condition
    end   
  end
end

module EZ
  module Where    
    module Base
        
      # EZ::Where plugin for generating the :conditions where clause
      # for ActiveRecord::Base.find. And an extension to ActiveRecord::Base
      # called AR::Base.find_with_conditions that takes a block and builds
      # the where clause dynamically for you.
      #
      def self.included(base)
        base.extend(ClassMethods)
      end

      # This method is the ez_where equivalent of to_str (accompanied by to_s)
      # so we have to_c and to_cond for native conversion to conditions
      # in this case the model's attributes hash or primary key is used to
      # construct a condition to retrieve this object (uniquely if primary key)
      # Condition << triggers to_cond if available
      def to_cond
        cond = self.class.where_condition
        if attributes[self.class.primary_key].nil?
          attributes.each { |k, v| cond.clause([self.class.table_name, k]) == v unless v.to_s.empty? } 
        else
          cond.clause([self.class.table_name, self.class.primary_key]) == attributes[self.class.primary_key]
        end
        cond
      end

      module ClassMethods
                
        # find_where can take the same options that find can. So :first and :all as well as :joins and :include et al.
        # When you have no :includes, the lowercase singular name of the model your are using is passed into the block
        # @posts = Post.find_where(:all) { |post| post.body =~ '%ruby%' }
        # When you have :includes you must pass the model names into the block in alphabetical order. And only the top
        # level includes get passed to the block. So post (the model itself) is always first, then comment and tag get 
        # passed to the block in alphabetical order and :metatags doesn't get passed in at all.
        # @posts = Post.find_where(:all, :include => {:tags => :metatags, :comments => {}}) do |post, comment, tag|
        #   post.body =~ '%ruby%'
        #   comment.approved == 1
        #   tag.not
        # end
        def find_where(what, *args, &block)
          self.find(what, find_where_options(*args, &block))
        end
        alias :ez_where :find_where
        alias :find_with_block :find_where

        # find_where_options contains the bulk of find_where functionality. It returns a find compatible options Hash.
        def find_where_options(*args, &block)
          options = args.last.is_a?(Hash) ? args.last : {}
          options[:include] ||= []
          options[:include] = [options[:include]].flatten
          outer_mapping = options.delete(:outer) || {} # preset :outer value for each :include subcondition, defaults to :and
          outer_mapping.default = :and
          inner_mapping = options.delete(:inner) || {} # preset :inner value for each :include subcondition, defaults to :and
          inner_mapping.default = :and
          if block_given?
            klass = self.name.downcase.to_sym       
            conditions = [where_condition(:outer => outer_mapping[klass], :inner => inner_mapping[klass])] # conditions on self first
            if((num_block_params = block.arity - 1) > 0)
              assoc_includes = [ options[:include] ].flatten.inject([]) { |symbols, assoc| 
                assoc.kind_of?(Hash) ? symbols + assoc.keys : symbols << assoc.to_sym 
              }.sort { |a,b| a.to_s <=> b.to_s }             
              assoc_includes.slice(0, num_block_params).each do |assoc|
                assoc_klass = reflect_on_association(assoc).klass
                cond_options = {}
                cond_options[:base] = conditions.first
                cond_options[:outer] = outer_mapping[assoc]
                cond_options[:inner] = inner_mapping[assoc]
                conditions << assoc_klass.where_condition(cond_options)
              end
            end          
            yield *conditions
            if conditions.first.include_associations?
              options[:include] = options[:include].inject({}) { |hash, inc| hash[inc] = {}; hash } if options[:include].kind_of?(Array)
              options[:include].merge!(conditions.first.include_associations)
            end
            unless conditions.first.order_by.empty?  
              options[:order] = options[:order].blank? ? "" : "#{options[:order]}, "
              options[:order] << "#{conditions.first.order_by.join(', ')}"  
            end         
            condition = EZ::Where::Condition.new
            condition << options[:conditions] || []
            conditions.each { |co| condition << co }          
            options[:conditions] = condition.to_sql
          end
          if options[:include].empty?
            options.delete(:include)
          end
          options
        end

        # Returns model specific (table_name prefixed) Condition
        def where_condition(*args, &block)
          options = args.last.is_a?(Hash) ? args.last : {}
          options[:table_name] ||= table_name
          Condition.new(options, &block)
        end
        alias :ez_condition :where_condition
        alias :c :where_condition        
      
        def composition(name = :default, *args)
          cond_klass = name.to_s.classify
          if EZ::Where::Compositions.const_defined?(cond_klass)
            EZ::Where::Compositions.const_get(cond_klass).new(self, *args)
          else
            EZ::Where::Compositions.const_get(Default).new(self, *args)
          end
        end
        alias :cs :composition
      
        # We have to_c and to_cond for native conversion to conditions
        # in this case the model's type is set in STI situations otherwise 
        # it returns a nil condition; it's ignored then
        def to_cond
          cond = where_condition
          if column_names.include? self.inheritance_column
            cond.clause([self.table_name, self.inheritance_column]) == self.name.demodulize
          end
          cond
        end
      
      end

    end # Where module
  end # EZ module
end # Caboose module

ActiveRecord::Base.send :include, EZ::Where::Base