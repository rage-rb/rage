# frozen_string_literal: true

class Rage::OpenAPI::Parsers::YAML
  # @private
  class OptionalParam < String
  end

  def initialize(**)
  end

  def known_definition?(yaml)
    object = process_yaml(yaml) rescue nil
    !!object && object.is_a?(Enumerable)
  end

  def parse(yaml)
    __parse(process_yaml(yaml))
  end

  private

  def __parse(object)
    spec = {}

    if object.is_a?(Hash)
      spec = { "type" => "object", "properties" => {} }

      object.each do |key, value|
        key = OptionalParam.new(key[0...-1]) if key.end_with?("?")

        spec["properties"][key] = if value.is_a?(Enumerable)
          __parse(value)
        else
          type_to_spec(value)
        end
      end

      spec["required"] = spec["properties"].keys.select { |k| !k.is_a?(OptionalParam) }

    elsif object.is_a?(Array) && object.length == 1
      spec = { "type" => "array", "items" => object[0].is_a?(Enumerable) ? __parse(object[0]) : type_to_spec(object[0]) }

    elsif object.is_a?(Array)
      spec = { "type" => "string", "enum" => object }
    end

    spec
  end

  def type_to_spec(type)
    is_collection, type_str = if type.is_a?(String)
      Rage::OpenAPI.__try_parse_collection(type)
    else
      [false, type]
    end

    spec = Rage::OpenAPI.__type_to_spec(type_str) || { "type" => "string", "enum" => [type_str] }

    if is_collection
      { "type" => "array", "items" => spec }
    else
      spec
    end
  end

  def process_yaml(str)
    YAML.safe_load(str.gsub(/Array<([^>]+)>/, '[\1]'))
  end
end
