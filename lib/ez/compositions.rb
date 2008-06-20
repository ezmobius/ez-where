module EZ
  module Where
    module Compositions
      
      class Base < EZ::Where::Condition
        
        def initialize(klass, *args)
          super klass
          self.prepare(klass, *args)
        end
        
        def prepare(klass, *args)
        end             
      end
      
      class Default < Base      
      end  
      
    end
  end
end