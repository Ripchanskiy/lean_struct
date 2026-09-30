# frozen_string_literal: true

require_relative "lean_struct/version"
require_relative "lean_struct/schema"
require_relative "lean_struct/class_methods"
require_relative "lean_struct/instance_methods"
require_relative "lean_struct/filtered_inspect"

# Builds immutable Struct classes with type checks on construction.
#
#   User = LeanStruct.define do
#     attribute :id, Integer
#     attribute :name, String, nullable: true   # key required, value may be nil
#     attribute? :email, String                 # key may be omitted
#     attribute :token, String, sensitive: true # value hidden in errors and #inspect
#     attribute :address do                     # nested struct => User::Address
#       attribute :city, String
#     end
#     attribute :roles, Array do                # array of nested structs => User::Roles
#       attribute :code, String
#     end
#   end
#
#   User.new(id: 1, name: nil, address: { city: "Kyiv" }, roles: [])
module LeanStruct
  class Error < ArgumentError; end

  # Type matcher for true/false (Ruby has no Boolean class)
  module Bool
    def self.===(value)
      value.equal?(true) || value.equal?(false)
    end
  end

  Field = Struct.new(:name, :type, :nullable, :omittable, :many, :nested, :class_name, :sensitive,
                     keyword_init: true)

  FILTERED = "[FILTERED]"
  EMPTY_HASH = {}.freeze
  UNDEFINED = Object.new.freeze
  private_constant :UNDEFINED

  class << self
    def define(&block) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      raise Error, "LeanStruct.define requires a block" unless block

      fields = Schema.build(&block)
      raise Error, "LeanStruct.define requires at least one attribute" if fields.empty?

      klass = Struct.new(*fields.map(&:name), keyword_init: false)
      klass.instance_variable_set(:@fields, fields.freeze)
      klass.instance_variable_set(:@schema, fields.to_h { |field| [field.name, field] }.freeze)
      name_nested(klass, fields)
      make_immutable(klass, fields)
      klass.singleton_class.prepend(ClassMethods)
      klass.include(InstanceMethods)
      klass.include(FilteredInspect) if fields.any?(&:sensitive)
      klass
    end

    # @api private
    def cast(klass, field, value)
      return value if value.nil? && field.nullable
      return cast_one(klass, field, value) unless field.many
      return value.map { |item| cast_one(klass, field, item) } if value.is_a?(Array)

      invalid!(klass, field, value)
    end

    # @api private
    def dump(value)
      case value
      when Struct then value.to_h
      when Array then value.map { |item| dump(item) }
      else value
      end
    end

    # @api private
    def missing!(klass, field)
      raise Error, "[#{klass}.new] :#{field.name} is missing in Hash input"
    end

    # @api private
    def invalid!(klass, field, value)
      raise Error, "[#{klass}.new] #{filter(field, value)} (#{value.class}) has invalid type for :#{field.name}"
    end

    # @api private
    def filter(field, value)
      field.sensitive && !value.nil? ? FILTERED : value.inspect
    end

    # @api private
    # Only the class: the whole input (e.g. ENV) must never end up in the message
    def not_hash!(klass, value)
      raise Error, "[#{klass}.new] #{value.class} has invalid type (Hash expected)"
    end

    private

    def cast_one(klass, field, value)
      return value if field.type === value # rubocop:disable Style/CaseEquality
      # nil nested input is treated as {} (valid when all nested keys are omittable)
      return field.type.new(value || EMPTY_HASH) if field.nested && (value.nil? || value.is_a?(Hash))

      invalid!(klass, field, value)
    end

    # User::Address, User::Roles, or the explicit class_name: option
    def name_nested(klass, fields)
      fields.select(&:nested).each do |field|
        klass.const_set(field.class_name || camelize(field.name), field.type)
      end
    end

    def camelize(name)
      name.to_s.split("_").map(&:capitalize).join
    end

    def make_immutable(klass, fields)
      klass.send(:undef_method, :[]=)
      fields.each { |field| klass.send(:undef_method, :"#{field.name}=") }
    end
  end
end
