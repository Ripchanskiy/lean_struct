# frozen_string_literal: true

require_relative "lib/lean_struct/version"

Gem::Specification.new do |spec|
  spec.name = "lean_struct"
  spec.version = LeanStruct::VERSION
  spec.authors = ["Serhii Ripchanskyi"]
  spec.email = ["sergeyripchanskiy@gmail.com"]

  spec.summary = "Immutable, type-checked Struct classes with a small DSL and zero dependencies."
  spec.description = "LeanStruct builds plain Ruby Struct classes with type checks, optional and nullable " \
                     "attributes, nested structs and recursive to_h. A lightweight, dependency-free " \
                     "alternative to Dry::Struct for simple entities."
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["rubygems_mfa_required"] = "true"
  spec.homepage = "https://github.com/Ripchanskiy/lean_struct"
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"

  spec.files = Dir["lib/**/*.rb", "README.md", "CHANGELOG.md", "LICENSE.txt"]
  spec.require_paths = ["lib"]
end
