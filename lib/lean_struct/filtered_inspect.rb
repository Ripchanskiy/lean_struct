# frozen_string_literal: true

module LeanStruct
  # Included only into structs that have sensitive: true attributes.
  # Masks their values in #inspect, #to_s and pp (nil stays visible: "not set" is not a secret).
  # #to_h and readers still return real values.
  module FilteredInspect
    def inspect
      schema = self.class.schema
      pairs = each_pair.map do |name, value|
        "#{name}=#{LeanStruct.filter(schema[name], value)}"
      end
      ["#<struct", self.class.name, pairs.join(", ")].compact.join(" ").concat(">")
    end

    alias to_s inspect

    def pretty_print(printer)
      printer.text(inspect)
    end
  end
end
