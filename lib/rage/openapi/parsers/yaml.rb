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
      required = []

      object.each do |key, value|
        is_optional = key.end_with?("?")
        clean_key = is_optional ? key.chomp("?") : key
        required << clean_key unless is_optional

        spec["properties"][clean_key] = if value.is_a?(Enumerable)
          __parse(value)
        else
          type_to_spec(value)
        end
      end

      spec["required"] = required unless required.empty?

    elsif object.is_a?(Array) && object.length == 1
      spec = { "type" => "array", "items" => object[0].is_a?(Enumerable) ? __parse(object[0]) : type_to_spec(object[0]) }

    elsif object.is_a?(Array)
      spec = { "type" => "string", "enum" => object }
    end

    spec
  end

  private

  def type_to_spec(type)
    if type.is_a?(String)
      is_collection, inner = Rage::OpenAPI.__try_parse_collection(type)
      if is_collection
        items_spec = if inner.include?(",")
                       { "type" => "string", "enum" => inner.split(",").map(&:strip) }
                     else
                       Rage::OpenAPI.__type_to_spec(inner) || { "type" => "string", "enum" => [inner] }
                     end
        return { "type" => "array", "items" => items_spec }
      end
    end

    Rage::OpenAPI.__type_to_spec(type) || { "type" => "string", "enum" => [type] }
  end
end
