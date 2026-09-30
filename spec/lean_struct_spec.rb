# frozen_string_literal: true

RSpec.describe LeanStruct do
  let(:user_class) do
    LeanStruct.define do
      attribute :id, Integer
      attribute :name, String, nullable: true
      attribute? :email, String
      attribute? :nickname, String, nullable: true
      attribute :active, LeanStruct::Bool
      attribute :address do
        attribute :city, String
        attribute? :zip, String
      end
      attribute :roles, Array do
        attribute :code, String
      end
    end
  end

  let(:attrs) do
    { id: 1, name: "Ann", active: true, address: { city: "Kyiv" }, roles: [{ code: "admin" }] }
  end

  it "has a version number" do
    expect(LeanStruct::VERSION).to match(/\A\d+\.\d+\.\d+\z/)
  end

  describe ".define" do
    it "returns a Struct subclass" do
      expect(user_class.ancestors).to include(Struct)
      expect(user_class.members).to eq(%i[id name email nickname active address roles])
    end

    it "requires a block" do
      expect { described_class.define }.to raise_error(LeanStruct::Error, /requires a block/)
    end

    it "requires at least one attribute" do
      expect { described_class.define {} }.to raise_error(LeanStruct::Error, /at least one attribute/) # rubocop:disable Lint/EmptyBlock
    end

    it "rejects duplicate attributes" do
      expect do
        described_class.define do
          attribute :id, Integer
          attribute :id, String
        end
      end.to raise_error(LeanStruct::Error, /:id is already defined/)
    end

    it "requires a type or a block" do
      expect { described_class.define { attribute :id } }.to raise_error(LeanStruct::Error, /requires a type/)
    end
  end

  describe "nested class names" do
    before { stub_const("User", user_class) }

    it "names nested classes after the attribute" do
      expect(User::Address.name).to eq("User::Address")
      expect(User::Roles.name).to eq("User::Roles")
    end

    it "accepts an explicit class_name" do
      klass = described_class.define do
        attribute :items, Array, class_name: "Item" do
          attribute :id, Integer
        end
      end
      stub_const("Order", klass)

      expect(Order::Item.name).to eq("Order::Item")
      expect(Order.new(items: [{ id: 1 }]).items.first).to be_a(Order::Item)
    end
  end

  describe ".new" do
    subject(:user) { user_class.new(attrs) }

    it "builds readers and nested structs" do
      expect(user.id).to eq(1)
      expect(user.address.city).to eq("Kyiv")
      expect(user.roles.map(&:code)).to eq(["admin"])
      expect(user.address).to be_a(user_class.schema[:address].type)
    end

    it "accepts keyword arguments" do
      expect(user_class.new(**attrs)).to eq(user)
    end

    it "has .call and .[] aliases" do
      expect(user_class.call(attrs)).to eq(user)
      expect(user_class[attrs]).to eq(user)
    end

    it "returns the same object for an instance of the class" do
      expect(user_class.new(user)).to equal(user)
      expect(user_class.call(user)).to equal(user)
    end

    it "accepts already built nested structs" do
      address = user_class.schema[:address].type.new(city: "Lviv")
      expect(user_class.new(attrs.merge(address:)).address).to equal(address)
    end

    it "ignores unknown keys" do
      expect(user_class.new(attrs.merge(unknown: 1)).to_h).not_to have_key(:unknown)
    end

    it "requires symbol keys" do
      expect { user_class.new(attrs.transform_keys(&:to_s)) }
        .to raise_error(LeanStruct::Error, /\] :id is missing in Hash input\z/)
    end

    it "raises when input is not a Hash, showing only its class" do
      expect { user_class.new([attrs]) }
        .to raise_error(LeanStruct::Error, /\] Array has invalid type \(Hash expected\)\z/)
    end

    it "never puts non-Hash input into the message" do
      expect { user_class.new(ENV) }.to raise_error(LeanStruct::Error) { |error|
        expect(error.message).to end_with("] Object has invalid type (Hash expected)")
      }
    end

    it "raises LeanStruct::Error which is an ArgumentError" do
      expect(LeanStruct::Error.ancestors).to include(ArgumentError)
    end

    context "with required attributes" do
      it "raises when the key is missing" do
        expect { user_class.new(attrs.except(:id)) }.to raise_error(LeanStruct::Error, /:id is missing/)
      end

      it "raises on a wrong type without coercion" do
        expect { user_class.new(attrs.merge(id: "1")) }
          .to raise_error(LeanStruct::Error, "[#{user_class}.new] \"1\" (String) has invalid type for :id")
      end

      it "raises on nil" do
        expect { user_class.new(attrs.merge(id: nil)) }.to raise_error(LeanStruct::Error, /for :id/)
      end
    end

    context "with nullable: true" do
      it "accepts nil" do
        expect(user_class.new(attrs.merge(name: nil)).name).to be_nil
      end

      it "still requires the key" do
        expect { user_class.new(attrs.except(:name)) }.to raise_error(LeanStruct::Error, /:name is missing/)
      end
    end

    context "with attribute? (omittable)" do
      it "allows the key to be omitted" do
        expect(user_class.new(attrs).email).to be_nil
      end

      it "does not allow nil unless nullable" do
        expect { user_class.new(attrs.merge(email: nil)) }.to raise_error(LeanStruct::Error, /for :email/)
      end

      it "allows nil when nullable" do
        expect(user_class.new(attrs.merge(nickname: nil)).to_h).to include(nickname: nil)
      end
    end

    context "with LeanStruct::Bool" do
      it "accepts true and false" do
        expect(user_class.new(attrs.merge(active: false)).active).to be(false)
      end

      it "rejects truthy values" do
        expect { user_class.new(attrs.merge(active: "true")) }.to raise_error(LeanStruct::Error, /for :active/)
      end
    end

    context "with nested structs" do
      it "validates nested input" do
        expect { user_class.new(attrs.merge(address: { city: 1 })) }
          .to raise_error(LeanStruct::Error, /has invalid type for :city/)
      end

      it "treats nil as {} (valid only when all nested keys are omittable)" do
        klass = described_class.define do
          attribute :meta do
            attribute? :note, String
          end
        end

        expect(klass.new(meta: nil).to_h).to eq(meta: {})
        expect { user_class.new(attrs.merge(address: nil)) }.to raise_error(LeanStruct::Error, /:city is missing/)
      end

      it "rejects non-hash values" do
        expect { user_class.new(attrs.merge(address: "Kyiv")) }.to raise_error(LeanStruct::Error, /for :address/)
      end
    end

    context "with arrays of nested structs" do
      it "accepts an empty array" do
        expect(user_class.new(attrs.merge(roles: [])).roles).to eq([])
      end

      it "rejects a non-array value" do
        expect { user_class.new(attrs.merge(roles: { code: "admin" })) }
          .to raise_error(LeanStruct::Error, /for :roles/)
      end

      it "validates each item" do
        expect { user_class.new(attrs.merge(roles: [{ code: 1 }])) }
          .to raise_error(LeanStruct::Error, /for :code/)
      end
    end

    context "with a plain Array type" do
      it "checks only the container" do
        klass = described_class.define { attribute :tags, Array }

        expect(klass.new(tags: [1, "a"]).tags).to eq([1, "a"])
        expect { klass.new(tags: "a") }.to raise_error(LeanStruct::Error, /for :tags/)
      end
    end

    context "with custom matchers" do
      it "accepts anything that responds to ===" do
        klass = described_class.define do
          attribute :age, 0..150
          attribute :code, /\A[A-Z]{2}\z/
          attribute :even, ->(value) { value.is_a?(Integer) && value.even? }
        end

        expect(klass.new(age: 30, code: "UA", even: 2).to_h).to eq(age: 30, code: "UA", even: 2)
        expect { klass.new(age: 200, code: "UA", even: 2) }.to raise_error(LeanStruct::Error, /for :age/)
      end
    end
  end

  describe "#to_h" do
    subject(:user) { user_class.new(attrs) }

    it "returns a recursive hash in declaration order" do
      expect(user.to_h).to eq(
        id: 1, name: "Ann", active: true, address: { city: "Kyiv" }, roles: [{ code: "admin" }]
      )
      expect(user.to_h.keys).to eq(%i[id name active address roles])
    end

    it "leaves out omitted keys, including nested ones" do
      expect(user.to_h).not_to have_key(:email)
      expect(user.to_h[:address]).not_to have_key(:zip)
    end

    it "keeps keys passed explicitly" do
      expect(user_class.new(attrs.merge(email: "a@b.c")).to_h).to include(email: "a@b.c")
    end

    it "supports a block like Hash#to_h" do
      expect(user.to_h { |key, value| [key.to_s, value] }.keys.first).to eq("id")
    end

    it "is aliased as #to_hash and #attributes" do
      expect(user.to_hash).to eq(user.to_h)
      expect(user.attributes).to eq(user.to_h)
      expect({ **user }).to eq(user.to_h)
    end
  end

  describe "immutability" do
    subject(:user) { user_class.new(attrs) }

    it "has no attribute writers" do
      expect(user).not_to respond_to(:id=)
      expect { user[:id] = 2 }.to raise_error(NoMethodError)
    end
  end

  describe "Struct behaviour" do
    subject(:user) { user_class.new(attrs) }

    it "compares by value" do
      expect(user).to eq(user_class.new(attrs))
      expect(user).not_to eq(user_class.new(attrs.merge(id: 2)))
    end

    it "supports pattern matching" do
      result =
        case user
        in { id: Integer => id, address: { city: } } then [id, city]
        end

      expect(result).to eq([1, "Kyiv"])
    end
  end

  describe "sensitive: true" do
    let(:config_class) do
      LeanStruct.define do
        attribute :host, String
        attribute :password, String, sensitive: true
        attribute :api_key, /\A[a-f0-9]{8}\z/, sensitive: true
        attribute? :tokens, Array, sensitive: true
      end
    end

    let(:config) { config_class.new(host: "db", password: "s3cret", api_key: "deadbeef") }

    it "shows nil, since an unset value is not a secret" do
      expect { config_class.new(host: "db", password: nil, api_key: "deadbeef") }
        .to raise_error(LeanStruct::Error, /\] nil \(NilClass\) has invalid type for :password/)
    end

    it "hides the value in type errors but keeps its class" do
      expect { config_class.new(host: "db", password: 123_456, api_key: "deadbeef") }
        .to raise_error(LeanStruct::Error, "[#{config_class}.new] [FILTERED] (Integer) has invalid type for :password")
    end

    it "hides the value when a format check fails" do
      expect { config_class.new(host: "db", password: "s3cret", api_key: "deadbeef\n") }
        .to raise_error(LeanStruct::Error) { |error| expect(error.message).not_to include("deadbeef") }
    end

    it "keeps values of other attributes in errors" do
      expect { config_class.new(host: 1, password: "s3cret", api_key: "deadbeef") }
        .to raise_error(LeanStruct::Error, /\] 1 \(Integer\) has invalid type for :host/)
    end

    it "masks values in #inspect, #to_s and pp" do
      stub_const("Config", config_class)
      expected = '#<struct Config host="db", password=[FILTERED], api_key=[FILTERED], tokens=nil>'

      expect(config.inspect).to eq(expected)
      expect(config.to_s).to eq(expected)
      expect { pp config }.to output("#{expected}\n").to_stdout
    end

    it "masks inside parent structs too" do
      parent = LeanStruct.define do
        attribute :db do
          attribute :password, String, sensitive: true
        end
      end

      expect(parent.new(db: { password: "s3cret" }).inspect).not_to include("s3cret")
    end

    it "keeps real values in readers and #to_h" do
      expect(config.password).to eq("s3cret")
      expect(config.to_h).to include(password: "s3cret", api_key: "deadbeef")
    end

    it "does not change #inspect of structs without sensitive attributes" do
      plain = LeanStruct.define { attribute :id, Integer }

      expect(plain.new(id: 1).inspect).to eq("#<struct id=1>")
      expect(plain.ancestors).not_to include(LeanStruct::FilteredInspect)
    end

    it "is exposed in the schema" do
      expect(config_class.schema[:password].sensitive).to be(true)
      expect(config_class.schema[:host].sensitive).to be(false)
    end
  end

  describe "class API" do
    it "exposes the schema" do
      expect(user_class.schema.keys).to eq(user_class.attribute_names)
      expect(user_class.schema[:email]).to have_attributes(omittable: true, nullable: false)
      expect(user_class.schema[:roles]).to have_attributes(nested: true, many: true)
    end

    it "does not let helper methods shadow attributes" do
      klass = described_class.define do
        attribute :schema, String
        attribute :attributes, String
      end

      entity = klass.new(schema: "a", attributes: "b")
      expect([entity.schema, entity.attributes]).to eq(%w[a b])
    end
  end
end
