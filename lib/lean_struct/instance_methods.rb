# frozen_string_literal: true

module LeanStruct
  # Included (not prepended), so attribute readers with the same names still win
  module InstanceMethods
    # Recursive hash; keys omitted on input are left out
    def to_h(&block) # rubocop:disable Metrics/MethodLength
      omitted = @__omitted__
      hash = {}
      if omitted
        bit = 1
        each_pair do |name, value|
          hash[name] = LeanStruct.dump(value) if omitted.nobits?(bit)
          bit <<= 1
        end
      else
        each_pair { |name, value| hash[name] = LeanStruct.dump(value) }
      end
      block ? hash.to_h(&block) : hash
    end

    alias to_hash to_h
    alias attributes to_h
  end
end
