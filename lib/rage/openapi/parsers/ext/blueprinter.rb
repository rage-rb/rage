# frozen_string_literal: true

class Rage::OpenAPI::Parsers::Ext::Blueprinter
  class InvalidViewError < StandardError; end

  def initialize(namespace: Object, root: Rage::OpenAPI::Nodes::Root.new, **)
    @namespace = namespace
    @root = root
    @parsing_stack = Set.new
  end

  def known_definition?(str)
    _, str, _ = Rage::OpenAPI.__parse_serializer_args(str)
    defined?(Blueprinter::Base) && @namespace.const_get(str).ancestors.include?(Blueprinter::Base)
  rescue NameError
    false
  end

  def parse(klass_str)
    is_collection, raw_klass_str, serializer_options = Rage::OpenAPI.__parse_serializer_args(klass_str)
    klass = @namespace.const_get(raw_klass_str)
    schema = build_schema(klass, is_collection, serializer_options)

    if @root.schema_registry.key?(raw_klass_str)
      @root.schema_registry[raw_klass_str] = is_collection ? schema["items"] : schema
    end

    schema
  rescue InvalidViewError => e
    Rage::OpenAPI.__log_warn e.message
  end

  private

  def build_schema(klass, is_collection, serializer_options = nil)
    @parsing_stack.add(klass.name)

    view_name = serializer_options&.key?(:view) ? serializer_options[:view] : :default
    reflections = klass.reflections
    view = reflections[view_name]
    raise InvalidViewError, "invalid view #{view_name}" unless view

    identifier_fields = extract_fields(reflections[:identifier])
    default_fields = extract_fields(view)
    association_fields = extract_associations(view)

    @parsing_stack.delete(klass.name)

    properties = identifier_fields.merge(default_fields.merge(association_fields).sort.to_h)

    schema = if serializer_options&.key?(:root)
      { serializer_options[:root].to_s => { "type" => "object", "properties" => properties } }
    else
      properties
    end

    result = { "type" => "object" }
    result["properties"] = schema if schema.any?
    result = { "type" => "array", "items" => result } if is_collection
    result
  end

  def extract_fields(view)
    view.fields.each_with_object({}) do |(_, field), properties|
      properties[field.display_name.to_s] = { "type" => "string" }
    end
  end

  def extract_associations(view)
    view.associations.each_with_object({}) do |(_, association), properties|
      blueprint = association.blueprint
      name, display_name = association.name.to_s, association.display_name.to_s
      is_collection = collection_association?(name)

      item_schema = if blueprint.is_a?(Proc)
        { "type" => "object" }
      elsif @parsing_stack.include?(blueprint.name)
        @root.schema_registry[blueprint.name] ||= nil
        { "$ref" => "#/components/schemas/#{blueprint.name}" }
      else
        build_schema(blueprint, false)
      end

      properties[display_name] = is_collection ? { "type" => "array", "items" => item_schema } : item_schema
    end
  end

  def collection_association?(name)
    return true unless name.respond_to?(:singularize)

    name.singularize != name
  end
end
