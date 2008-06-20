class Hash #:nodoc:  
 
  def to_sql(param = 'AND')
    ActiveRecord::Base.send :sanitize_sql, self.to_conditions
  end
 
  def to_conditions(param = 'AND')
    [map { |k, v| "#{k} #{ActiveRecord::Base.send(:attribute_condition, v)}" }.join(" #{param} "), *values]
  end
  
  alias :to_sql_conditions :to_conditions
 
  def to_named_conditions(param = 'AND')
    [map { |k, v| k.to_s+' = :'+k }.join(' '+param+' '), self.symbolize_keys]
  end 
   
end