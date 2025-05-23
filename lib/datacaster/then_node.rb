module Datacaster
  class ThenNode < Base
    def initialize(left, then_caster, else_caster = nil)
      @left = left
      @then = then_caster
      @else = else_caster
    end

    def else(else_caster)
      raise ArgumentError.new("Datacaster: double else clause is not permitted") if @else

      self.class.new(@left, @then, DefinitionDSL.expand(else_caster))
    end

    def cast(object, runtime:)
      unless @else
        raise ArgumentError.new('Datacaster: use "a & b" instead of "a.then(b)" when there is no else-clause')
      end

      left_result = @left.with_runtime(runtime).(object)

      if left_result.valid?
        @then.with_runtime(runtime).(left_result.value)
      else
        @else.with_runtime(runtime).(object)
      end
    end

    def to_json_schema
      unless @else
        raise ArgumentError.new('Datacaster: use "a & b" instead of "a.then(b)" when there is no else-clause')
      end

      left = @left.to_json_schema

      JsonSchemaResult.new(
        "oneOf" => [
          (@left & @then).to_json_schema,
          JsonSchemaResult.new("not" => left).apply(@else.to_json_schema)
        ]
      )
    end

    def to_json_schema_attributes
      super.merge(
        required:
          @left.to_json_schema_attributes[:required] &&
            @else.to_json_schema_attributes[:required]
      )
    end

    def inspect
      "#<Datacaster::ThenNode Then: #{@then.inspect} Else: #{@else.inspect}>"
    end
  end
end
