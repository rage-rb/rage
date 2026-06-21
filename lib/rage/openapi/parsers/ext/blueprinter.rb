# frozen_string_literal: true

class Rage::OpenAPI::Parsers::Ext::Blueprinter
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
    is_collection, raw_klass_str, _ = Rage::OpenAPI.__parse_serializer_args(klass_str)
    klass = @namespace.const_get(raw_klass_str)
    schema = build_schema(klass, is_collection)

    if @root.schema_registry.key?(raw_klass_str)
      @root.schema_registry[raw_klass_str] = is_collection ? schema["items"] : schema
    end

    schema
  end

  private

  def build_schema(klass, is_collection)
    @parsing_stack.add(klass.name)

    reflections = klass.reflections
    identifier_fields = extract_fields(reflections, :identifier)
    default_fields = extract_fields(reflections, :default)
    association_fields = extract_associations(reflections, :default)

    @parsing_stack.delete(klass.name)

    schema = identifier_fields.merge(default_fields.merge(association_fields).sort.to_h)

    result = { "type" => "object" }
    result["properties"] = schema if schema.any?
    result = { "type" => "array", "items" => result } if is_collection
    result
  end

  def extract_fields(reflections, view_name)
    return {} unless (view = reflections[view_name])

    view.fields.each_with_object({}) do |(_, field), hash|
      hash[field.display_name.to_s] = { "type" => "string" }
    end
  end

  def extract_associations(reflections, view_name)
    return {} unless (view = reflections[view_name])

    view.associations.each_with_object({}) do |(_, association), hash|
      blueprint = resolve_blueprint(association.blueprint)
      name = association.display_name.to_s
      is_collection = collection_association?(name)

      if blueprint.nil?
        item_schema = { "type" => "string" }
      elsif @parsing_stack.include?(blueprint.name)
        @root.schema_registry[blueprint.name] ||= nil
        item_schema = { "$ref" => "#/components/schemas/#{blueprint.name}" }
      else
        item_schema = build_schema(blueprint, false)
      end

      hash[name] = is_collection ? { "type" => "array", "items" => item_schema } : item_schema
    end
  end

  private

  def resolve_blueprint(blueprint)
    return blueprint unless blueprint.respond_to?(:call)

    begin
      blueprint.call(nil)
    rescue
      nil
    end
  end

  def collection_association?(name)
    return true unless name.respond_to?(:singularize)

    name.singularize != name
  end
end
