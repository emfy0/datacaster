module Datacaster
  class AndNode < Base
    def initialize(*casters)
      @casters = casters
    end

    def cast(object, runtime:)
      Datacaster.ValidResult(
        @casters.reduce(object) do |result, caster|
          caster_result = caster.with_runtime(runtime).(result)
          return caster_result unless caster_result.valid?
          caster_result.value
        end
      )
    end

    def to_json_schema
      result =
        @casters.reduce(JsonSchemaResult.new) do |result, caster|
          result.apply(caster.to_json_schema, caster.to_json_schema_attributes)
        end

      mapping =
        @casters.reduce({}) do |result, caster|
          result.merge(caster.to_json_schema_attributes[:remaped])
        end

      result.remap(mapping)
    end

    def to_json_schema_attributes
      super.merge(
        required:
          @casters.any? { |caster| caster.to_json_schema_attributes[:required] },
        picked:
          @casters.flat_map { |caster| caster.to_json_schema_attributes[:picked] },
        remaped:
          @casters.reduce({}) do |result, caster|
            result.merge(caster.to_json_schema_attributes[:remaped])
          end
      )
    end

    def inspect
      "#<Datacaster::AndNode casters: #{@casters.inspect}>"
    end
  end
end
