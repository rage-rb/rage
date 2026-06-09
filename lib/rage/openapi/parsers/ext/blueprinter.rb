# frozen_string_literal: true

class Rage::OpenAPI::Parsers::Ext::Blueprinter
  def initialize(namespace: Object, root: Rage::OpenAPI::Nodes::Root.new, **)
    @namespace = namespace
    @root = root
  end

  def known_definition?(str)
    _, str, _ = Rage::OpenAPI.__parse_serializer_args(str)
    defined?(Blueprinter::Base) && @namespace.const_get(str).ancestors.include?(Blueprinter::Base)
  rescue NameError
    false
  end

  def parse(klass_str)
    is_collection, raw_klass_str, _ = Rage::OpenAPI.__parse_serializer_args(klass_str)
    klass = @namespace.const_get(raw_klass_str)
    build_schema(klass, is_collection)
  end

  private

  def build_schema(klass, is_collection)
    reflections = klass.reflections
    identifier_fields = extract_fields(reflections, :identifier)
    default_fields = extract_fields(reflections, :default)

    schema = identifier_fields.merge(default_fields.sort.to_h)

    result = { "type" => "object" }
    result["properties"] = schema if schema.any?
    result = { "type" => "array", "items" => result } if is_collection
    result
  end

  def extract_fields(reflections, view_name)
    return {} unless (view = reflections[view_name])

    view.instance_variable_get(:@view_collection).instance_variable_get(:@views)[view_name].instance_variable_get(:@fields).each_with_object({}) do |(_, field), hash|
      hash[field.name.to_s] = { "type" => "string" }
    end
  end
end
