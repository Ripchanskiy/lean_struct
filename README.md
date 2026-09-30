# LeanStruct

Immutable, type-checked `Struct` classes with a tiny DSL and **zero runtime dependencies**.

LeanStruct covers the part of [Dry::Struct](https://dry-rb.org/gems/dry-struct/) most apps use for
simple entities: strict type checks, optional and nullable attributes, nested structs, arrays of
nested structs and a recursive `to_h`. The result is a plain Ruby `Struct`, roughly 2–3× faster than
Dry::Struct (see [Performance](#performance)).

```ruby
User = LeanStruct.define do
  attribute :id, Integer
  attribute :name, String, nullable: true    # key required, value may be nil
  attribute? :email, String                  # key may be omitted
  attribute :active, LeanStruct::Bool
  attribute :address do                      # nested struct => User::Address
    attribute :city, String
  end
  attribute :roles, Array do                 # array of nested structs => User::Roles
    attribute :code, String
  end
end

user = User.new(id: 1, name: nil, active: true, address: { city: "Kyiv" }, roles: [{ code: "admin" }])
user.address.city # => "Kyiv"
user.to_h
# => { id: 1, name: nil, active: true, address: { city: "Kyiv" }, roles: [{ code: "admin" }] }

User.new(id: "1", name: nil, active: true, address: { city: "Kyiv" }, roles: [])
# => LeanStruct::Error: [User.new] "1" (String) has invalid type for :id
```

## Installation

```ruby
# Gemfile
gem "lean_struct"
```

Requires Ruby 3.1+.

## Usage

### Defining attributes

| DSL                                          | key        | `nil`     |
|----------------------------------------------|------------|-----------|
| `attribute :code, String`                    | required   | rejected  |
| `attribute :code, String, nullable: true`    | required   | accepted  |
| `attribute? :code, String`                   | may be omitted | rejected  |
| `attribute? :code, String, nullable: true`   | may be omitted | accepted  |

Any attribute also takes `sensitive: true` to hide its value in errors and `#inspect`
(see [Sensitive attributes](#sensitive-attributes)).

`attribute?` only allows the key to be **left out**. It does not allow `nil`. Use `nullable: true` for that.

```ruby
Tag = LeanStruct.define { attribute? :code, String }

Tag.new({})          # => ok, to_h == {}
Tag.new(code: "a")   # => ok
Tag.new(code: nil)   # => LeanStruct::Error
```

### Types

A type is anything that responds to `===`, checked as `type === value`. No coercion is done: `"1"` is not an `Integer`.
Any class works: `String`, `Float`, `Symbol`, `Hash`, `Time`, your own classes.

```ruby
LeanStruct.define do
  attribute :id, Integer                                      # class: value.is_a?(Integer)
  attribute :active, LeanStruct::Bool                         # true or false only
  attribute :age, 0..150                                      # Range
  attribute :country, /\A[A-Z]{2}\z/                          # Regexp
  attribute :even, ->(value) { value.is_a?(Integer) && value.even? } # lambda
  attribute :tags, Array                                      # any Array, items are not checked
end
```

### Nested structs

A block defines a nested struct. The nested class is named after the attribute (`User::Address`),
or after `class_name:` when given:

```ruby
Order = LeanStruct.define do
  attribute :customer do
    attribute :name, String
  end
  attribute :items, Array, class_name: "Item" do   # Array + block = array of nested structs
    attribute :sku, String
    attribute :quantity, Integer
  end
end

order = Order.new(customer: { name: "Ann" }, items: [{ sku: "A-1", quantity: 2 }])
order.items.first # => #<struct Order::Item sku="A-1", quantity=2>
```

- A nested value may be a `Hash` or an already built instance of the nested class.
- `nil` for a nested attribute is treated as `{}`. This is valid only when every nested key is optional (`attribute?`).
  Use `nullable: true` to keep `nil` as is.

### Input rules

- Keys must be **symbols**. `{ "id" => 1 }` fails with `:id is missing in Hash input`.
- **Unknown keys are ignored.**
- Both a hash and keyword arguments work: `User.new(hash)`, `User.new(**hash)`, `User.call(hash)`, `User[hash]`.
- `User.new(user)` returns the same `user` object, so `.call` is safe in pipelines that may already hold an entity.

### Reading

Instances are regular `Struct`s: readers, `[]`, `==`, `members`, `to_a`, `each`, `deconstruct` and
`deconstruct_keys` (pattern matching) all work.

```ruby
case user
in { id: Integer => id, address: { city: } } then [id, city]
end
```

`to_h` (aliases `to_hash` and `attributes`) is recursive and returns keys in declaration order.
**Keys omitted on input are left out**, so "not given" and "given as `nil`" stay distinguishable:

```ruby
Tag.new({}).to_h            # => {}
{ **user }                  # works thanks to to_hash
user.to_h { |k, v| [k.to_s, v] } # block form, like Hash#to_h
```

### Immutability

Writers are removed: `user.id = 2` and `user[:id] = 2` raise `NoMethodError`.

Immutability is shallow, as in Dry::Struct. Neither instances nor their values are frozen:

- `user.tags << "admin"` changes the struct (so does `user.name << "x"`, if the string is not frozen);
- a plain `Array` attribute keeps the caller's array, so changing it outside changes the struct too;
- arrays of nested structs are built anew, but you can still append items to them.

If you need deep immutability, freeze the input data before building the struct.

### Errors

Every validation failure raises `LeanStruct::Error`, a subclass of `ArgumentError`:

```
[User.new] :id is missing in Hash input
[User.new] "1" (String) has invalid type for :id
[User.new] Array has invalid type (Hash expected)
[User::Address.new] 1 (Integer) has invalid type for :city
```

Messages include the `inspect` of the rejected value, which helps when an upstream API changes a type.
Two exceptions keep data out of logs and error trackers:

- When the input is not a Hash, only its class is shown, so `Config.new(ENV)` or a raw HTTP response never
  ends up in the message.
- Values of `sensitive: true` attributes are replaced with `[FILTERED]` (see below).

### Sensitive attributes

Mark secrets with `sensitive: true`, which is useful for configs built from ENV or YAML:

```ruby
Config = LeanStruct.define do
  attribute :host, String
  attribute :password, String, sensitive: true
  attribute :api_key, /\A[a-f0-9]{32}\z/, sensitive: true
end

Config.new(host: "db", password: 123456, api_key: key)
# => LeanStruct::Error: [Config.new] [FILTERED] (Integer) has invalid type for :password

config = Config.new(host: "db", password: "s3cret", api_key: key)
config.inspect   # => #<struct Config host="db", password=[FILTERED], api_key=[FILTERED]>
config.password  # => "s3cret"
config.to_h      # => { host: "db", password: "s3cret", api_key: "..." }
```

- The value is hidden in error messages, `#inspect`, `#to_s` and `pp`. The class is still shown in errors,
  so you can see that YAML turned `123456` into an `Integer`.
- `nil` is shown as is: "not set" is not a secret.
- Readers and `#to_h` return real values: `to_h` is data, not a log line.
- It applies to the attribute's own value. For a nested struct, mark the nested attributes themselves.
- Structs without sensitive attributes keep the standard `Struct#inspect`.

### Class API

```ruby
User.attribute_names       # => [:id, :name, :email, :active, :address, :roles]
User.schema[:email]        # => #<struct LeanStruct::Field name=:email, type=String, nullable=false, omittable=true, ...>
```

## Comparison with Dry::Struct

### DSL

| Dry::Struct                                       | LeanStruct                                        |
|---------------------------------------------------|---------------------------------------------------|
| `class User < Dry::Struct`                        | `User = LeanStruct.define do ... end`             |
| `attribute :id, Types::Integer`                   | `attribute :id, Integer`                          |
| `attribute :name, Types::String.optional`         | `attribute :name, String, nullable: true`         |
| `attribute? :code, Types::String`                 | `attribute? :code, String`                        |
| `attribute? :code, Types::String.optional`        | `attribute? :code, String, nullable: true`        |
| `attribute :active, Types::Bool`                  | `attribute :active, LeanStruct::Bool`             |
| `attribute :address do ... end`                   | `attribute :address do ... end`                   |
| `attribute :roles, Types::Array do ... end`       | `attribute :roles, Array do ... end`              |

### Same behaviour

Compared with Dry::Struct using the strict `Dry.Types()` types:

| input                                           | result (both)                         |
|-------------------------------------------------|---------------------------------------|
| unknown key                                     | ignored                               |
| string keys                                     | error: key is missing                 |
| missing required key                            | error                                 |
| omitted `attribute?`                            | ok, key left out of `to_h`            |
| `nil` for a non-optional / non-nullable key     | error                                 |
| `"1"` for an `Integer` attribute                | error, no coercion                    |
| `nil` for a nested struct with only `attribute?` keys | `{}`                            |
| non-array for an array attribute                | error                                 |
| input is not a Hash                             | error                                 |
| `Klass.new(instance)`                           | returns the same instance             |
| `to_h` / `to_hash`                              | recursive hash                        |
| writers                                         | none                                  |
| `==`                                            | by value                              |

### Differences

| aspect                          | Dry::Struct                                          | LeanStruct                                  |
|---------------------------------|------------------------------------------------------|---------------------------------------------|
| base class                      | `Dry::Struct`                                        | Ruby `Struct`                               |
| dependencies                    | dry-struct, dry-types, dry-core, dry-logic, dry-inflector, ... | none                              |
| error class                     | `Dry::Struct::Error`                                 | `LeanStruct::Error < ArgumentError`         |
| error message                   | `... has invalid type for :id violates constraints (type?(Integer, "1") failed)` | `... has invalid type for :id` |
| secrets in errors / `#inspect`  | shown                                                | hidden with `sensitive: true`; non-Hash input shows only its class |
| array item class name           | singularized: `roles` → `User::Role`                 | as the attribute: `User::Roles`, or `class_name:` |
| `Struct` API (`to_a`, `each`, `members`) | no (`attribute_names`, `schema`)            | yes, plus `attribute_names` and `schema`   |
| `entity.new(changes)` (copy with changes) | yes                                        | no                                          |
| defaults, coercion, constraints, `transform_keys`, custom constructors | yes           | no                                          |
| inheritance (`class Admin < User`) | yes                                               | no                                          |

If you need coercion, defaults or composable types, use Dry::Struct. If your entities are
"validate a hash from an API and serialize it back", LeanStruct does that with less overhead.

### Performance

Ruby 3.4.10, dry-struct 1.8.1, Apple Silicon, 50 000 iterations, median of 5 runs.
*Flat*: 5 scalar attributes, one of them omitted. *Nested*: 3 nested structs, an array of 2 nested structs and a bool.

| operation       | Dry::Struct, ms | LeanStruct, ms | LeanStruct faster by |
|-----------------|----------------:|---------------:|---------------------:|
| flat `.new`     | 135.2           | 59.1           | 2.3×                 |
| flat `#to_h`    | 96.5            | 44.0           | 2.2×                 |
| nested `.new`   | 511.1           | 274.0          | 1.9×                 |
| nested `#to_h`  | 490.8           | 166.1          | 3.0×                 |

## Development

```sh
bundle install
bundle exec rake        # specs + rubocop
```

## License

[MIT](LICENSE.txt)
