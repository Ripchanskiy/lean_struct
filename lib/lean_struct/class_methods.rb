# frozen_string_literal: true

module LeanStruct
  # Prepended to the struct's singleton class, so it wraps Struct's own .new and .[]
  module ClassMethods
    attr_reader :schema

    # Kept in one piece on purpose: hot path, no extra method calls per field
    def new(attrs = EMPTY_HASH) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
      return attrs if attrs.is_a?(self)

      LeanStruct.not_hash!(self, attrs) unless attrs.is_a?(Hash)

      omitted = 0 # bitmask of omitted keys: no allocation per instance
      bit = 1
      values = @fields.map do |field|
        value = attrs.fetch(field.name, UNDEFINED)
        if UNDEFINED.equal?(value)
          LeanStruct.missing!(self, field) unless field.omittable
          omitted |= bit
          value = nil
        elsif field.many || !(field.type === value) # rubocop:disable Style/CaseEquality
          value = LeanStruct.cast(self, field, value)
        end
        bit <<= 1
        value
      end

      instance = super(*values)
      instance.instance_variable_set(:@__omitted__, omitted) unless omitted.zero?
      instance
    end

    alias call new
    alias [] new

    def attribute_names
      members
    end
  end
end
