module Datacaster
  class AndWithErrorAggregationNode < Base
    def initialize(left, right)
      @left = left
      @right = right
    end

    # Works like AndNode, but doesn't stop at first error — in order to aggregate all Failures
    # Makes sense only for Hash Schemas
    def cast(object, runtime:)
      left_result = @left.with_runtime(runtime).(object)

      if left_result.valid?
        @right.with_runtime(runtime).(left_result.value)
      else
        right_result = @right.with_runtime(runtime).(object)
        if right_result.valid?
          left_result
        else
          Datacaster.ErrorResult(Utils.merge_errors(left_result.raw_errors, right_result.raw_errors))
        end
      end
    end


    def to_json_schema
      [@left, @right].reduce(JsonSchemaResult.new) do |result, caster|
        result.apply(caster.to_json_schema)
      end
    end

    def to_json_schema_attributes
      super.merge(
        required:
          [@left, @right].any? { |caster| caster.to_json_schema_attributes[:required] }
      )
    end

    def inspect
      "#<Datacaster::AndWithErrorAggregationNode L: #{@left.inspect} R: #{@right.inspect}>"
    end
  end
end
