module Datacaster
  class JsonSchemaAttributes < Base
    def initialize(base, schema_attributes = {}, &block)
      @base = base
      @schema_attributes = schema_attributes
      @block = block
    end

    def cast(object, runtime:)
      @base.cast(object, runtime: runtime)
    end

    def to_json_schema_attributes
      result = @base.to_json_schema_attributes
      result = result.merge(@schema_attributes)
      result = @block.(result) if @block
      result
    end

    def to_json_schema
      @base.to_json_schema
    end

    def inspect
      "#<#{self.class.name} base: #{@base.inspect}>"
    end
  end
end
