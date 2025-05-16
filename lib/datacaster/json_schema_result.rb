module Datacaster
  class JsonSchemaResult < Hash
    def initialize(from = {}, focus = nil)
      merge!(from)

      if from.is_a?(self.class)
        @focus = from.focus
      else
        @focus = []
      end

      if focus == false || @focus == false
        @focus = false
        return
      end

      @focus << focus if focus
      @target = self
      @focus.each { |k| @target = @target['properties'][k] }
    end

    def with_focus_key(key)
      result = apply(
        "type" => "object",
        "properties" => key ? { key => {} } : {}
      )
      self.class.new(result, key)
    end

    def without_focus
      self.class.new(self).reset_focus
    end

    def remap(mapping)
      return self if mapping.empty?

      if self['oneOf'] || self['anyOf']
        type = self.keys.first

        self[type] = self[type].map { |props| object_remap(props, mapping) }
      else
        object_remap(self, mapping)
      end

      self
    end

    def object_remap(value, mapping)
      return value unless value['type'] == 'object'

      mapping.each do |from, to|
        from_props = value['properties'][from] || {}
        to_props = value['properties'][to] || {}

        one_to_one_remap = mapping.values.count { _1 == to } == 1

        properties_from = value['properties'].delete(from)
        properties_to = value['properties'].delete(to)

        if from && (properties_to || properties_from)
          value['properties'][from] =
            if one_to_one_remap
              Datacaster::Utils.deep_merge(to_props, from_props)
            else
              self.class.new(properties_from || {})
            end
        end

        required_from = value['required']&.delete(from)
        required_to = value['required']&.delete(to)

        if from && one_to_one_remap && (required_from || required_to)
          value['required'] << from
        end
      end

      value
    end

    def apply(other, schema_attributes = {})
      return self if other.nil? || other.empty?
      return JsonSchemaResult.new(other) if empty?

      if @focus && !@focus.empty?
        return with_updated_target(JsonSchemaResult.new(@target).apply(other))
      end

      # validations after pick(a, b) & transform
      self_type = self['type']
      other_type = other['type']

      if (self_type == 'object' || self_type == 'array') && (other_type != 'object' && other_type != 'array')
        return JsonSchemaResult.new(self)
      end

      result = self.class.new({})

      if self['required'] || other['required']
        result['required'] = (
          (self['required'] || []).to_set | (other['required'] || []).to_set
        ).to_a
      end

      nested =
        if self['properties'] && (other['items'] || self['items']) ||
          self['items'] && (self['properties'] || other['properties']) ||
          other['items'] && other['properties']
          raise RuntimeError, "can't merge json schemas due to wrong items/properties combination " \
            "for #{self.inspect} and #{other.inspect}", caller
        elsif self['properties'] || other['properties']
          'properties'
        elsif self['items'] || other['items']
          'items'
        else
          nil
        end

      if nested
        result[nested] = {}

        keys = (self[nested] || {}).keys + (other[nested] || {}).keys
        keys = keys.to_set

        keys.each do |k|
          one_k = self[nested] && self[nested][k] || {}
          two_k = other[nested] && other[nested][k] || {}

          if !one_k.is_a?(Hash) || !two_k.is_a?(Hash)
            if one_k.empty? && !two_k.is_a?(Hash)
              result[nested][k] = two_k
            elsif two_k.empty? && !one_k.is_a?(Hash)
              result[nested][k] = one_k
            elsif one_k == two_k
              result[nested][k] = one_k
            else
              raise RuntimeError, "can't merge json schemas due to wrong items/properties combination " \
                "for #{self.inspect} and #{other.inspect}", caller
            end
          elsif one_k.is_a?(Hash) && two_k.is_a?(Hash)
            result[nested][k] = self.class.new(one_k).apply(two_k)
          else
            raise RuntimeError, "can't merge json schemas due to wrong items/properties combination " \
              "for #{self.inspect} and #{other.inspect}", caller
          end

        end
      end

      if self['description'] || other['description']
        result['description'] = other['description'] || self['description']
      end

      (self.keys + other.keys - %w(required properties items description)).to_set.each do |k|
        # used to merge switch schemas
        # TODO: подумать как сделать в обратную сторону
        #     FULL_DETAILS_SCHEMA = Datacaster.partial_schema do
            #   LoanTransferMethods::InitiatorTransferDetailsStruct.schema & switch(
            #     :kind,
            #     product: hash_schema(
            #       currency: string,
            #       us_only: boolean,
            #       name: string,
            #       values: array_of(integer),
            #       official_provider_name: string,
            #     )
            #   ).else(pass)
            # end

        if schema_attributes[:extendable]
          case k
          in 'oneOf'
            self_one_of = self[k]
            other_one_of = other[k]

            result_objects = other_one_of.map do |other_obj|
              other_obj_properties = other_obj['properties'].to_a

              max_same = -1

              # basicly is guessing here, but must be ok in most cases
              merge_candidate = self_one_of.max_by do |self_obj|
                next -1 if self_obj.empty?

                self_obj_properties = self_obj['properties'].to_a

                max_same = (self_obj_properties & other_obj_properties).size

                max_same
              end

              next other_obj if max_same < 1

              Datacaster::Utils.deep_merge(other_obj, merge_candidate)
            end

            next result[k] = result_objects
          else
            raise RuntimeError, "can't merge json schemas due to conflicting field #{k} for " \
              "#{inspect} and #{other.inspect}", caller
          end
        else
          if self[k] && other[k] && self[k] != other[k]
            raise RuntimeError, "can't merge json schemas due to conflicting field #{k} for " \
              "#{inspect} and #{other.inspect}", caller
          end
        end

        result[k] = other[k] || self[k]
      end

      result
    end

    protected

    def focus
      @focus
    end

    def reset_focus
      @focus = []
      @target = self
      self
    end

    private

    def with_updated_target(target)
      result = self.class.new(self)
      nested =
        @focus[0..-2].reduce(result) do |result, k|
          result['properties'][k] = result['properties'][k].dup
          result['properties'][k]
        end
      nested['properties'][@focus[-1]] = target
      result
    end
  end
end
