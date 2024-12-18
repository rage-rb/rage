# frozen_string_literal: true

class Rage::OpenAPI::Parsers::Ext::ActiveRecord
  BLACKLISTED_ATTRIBUTES = %w(id created_at updated_at)

  def initialize(namespace: Object, **)
    @namespace = namespace
  end

  def known_definition?(str)
    _, str = Rage::OpenAPI.__try_parse_collection(str)
    defined?(ActiveRecord::Base) && @namespace.const_get(str).ancestors.include?(ActiveRecord::Base)
  rescue NameError
    false
  end

  def parse(klass_str)
    is_collection, klass_str = Rage::OpenAPI.__try_parse_collection(klass_str)
    klass = @namespace.const_get(klass_str)

    schema = {}

    klass.attribute_types.each do |attr_name, attr_type|
      next if BLACKLISTED_ATTRIBUTES.include?(attr_name) ||
              attr_name.end_with?("_id") ||
              attr_name == klass.inheritance_column ||
              klass.defined_enums.include?(attr_name)

      schema[attr_name] = case attr_type.type
      when :integer
        { "type" => "integer" }
      when :boolean
        { "type" => "boolean" }
      when :binary
        { "type" => "string", "format" => "binary" }
      when :date
        { "type" => "string", "format" => "date" }
      when :datetime, :time
        { "type" => "string", "format" => "date-time" }
      when :float
        { "type" => "number", "format" => "float" }
      when :decimal
        { "type" => "number" }
      when :json
        { "type" => "object" }
      else
        { "type" => "string" }
      end
    end

    klass.defined_enums.each do |attr_name, mapping|
      schema[attr_name] = { "type" => "string", "enum" => mapping.keys }
    end

    result = { "type" => "object" }
    result["properties"] = schema if schema.any?

    result = { "type" => "array", "items" => result } if is_collection

    result
  end
end
