# frozen_string_literal: true

class Rage::OpenAPI::Parsers::YAML
  def initialize(**)
  end

  def known_definition?(yaml)
    object = YAML.safe_load(yaml) rescue nil
    !!object && object.is_a?(Enumerable)
  end

  def parse(yaml)
    __parse(YAML.safe_load(yaml))
  end

  private

  def __parse(object)
    spec = {}

    if object.is_a?(Hash)
      spec = { "type" => "object", "properties" => {} }

      object.each do |key, value|
        spec["properties"][key] = if value.is_a?(Enumerable)
          __parse(value)
        else
          type_to_spec(value)
        end
      end

    elsif object.is_a?(Array) && object.length == 1
      spec = { "type" => "array", "items" => object[0].is_a?(Enumerable) ? __parse(object[0]) : type_to_spec(object[0]) }

    elsif object.is_a?(Array)
      spec = { "type" => "string", "enum" => object }
    end

    spec
  end

  private

  def type_to_spec(type)
    case type
    when "Integer"
      { "type" => "integer" }
    when "Float"
      { "type" => "number", "format" => "float" }
    when "Numeric"
      { "type" => "number" }
    when "Boolean"
      { "type" => "boolean" }
    when "Hash"
      { "type" => "object" }
    when "Date"
      { "type" => "string", "format" => "date" }
    when "DateTime", "Time"
      { "type" => "string", "format" => "date-time" }
    when "String"
      { "type" => "string" }
    else
      { "type" => "string", "enum" => [type] }
    end
  end
end
