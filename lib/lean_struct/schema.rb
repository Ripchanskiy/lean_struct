# frozen_string_literal: true

module LeanStruct
  # DSL evaluated inside LeanStruct.define
  class Schema
    def self.build(&)
      schema = new
      schema.instance_eval(&)
      schema.fields
    end

    attr_reader :fields

    def initialize
      @fields = []
    end

    # attribute :id, Integer
    # attribute :name, String, nullable: true
    # attribute :address do ... end
    # attribute :roles, Array, class_name: "Role" do ... end
    # attribute :token, String, sensitive: true
    def attribute(name, type = nil, nullable: false, omittable: false, class_name: nil, sensitive: false, &block) # rubocop:disable Metrics/ParameterLists
      name = name.to_sym
      validate!(name, type, block)
      nested = LeanStruct.define(&block) if block
      @fields << Field.new(name:, type: nested || type, nullable:, omittable:, class_name:, sensitive:,
                           many: !nested.nil? && type == Array, nested: !nested.nil?)
    end

    # Same as #attribute, but the key may be omitted from input
    def attribute?(name, type = nil, **opts, &)
      attribute(name, type, **opts, omittable: true, &)
    end

    private

    def validate!(name, type, block)
      raise Error, "attribute :#{name} is already defined" if @fields.any? { |field| field.name == name }
      raise Error, "attribute :#{name} requires a type or a block" if type.nil? && block.nil?
    end
  end
end
