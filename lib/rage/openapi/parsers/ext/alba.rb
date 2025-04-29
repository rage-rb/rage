# frozen_string_literal: true

class Rage::OpenAPI::Parsers::Ext::Alba
  attr_reader :namespace

  def initialize(namespace: Object, **)
    @namespace = namespace
  end

  def known_definition?(str)
    _, str = Rage::OpenAPI.__try_parse_collection(str)
    defined?(Alba::Resource) && @namespace.const_get(str).ancestors.include?(Alba::Resource)
  rescue NameError
    false
  end

  def parse(klass_str)
    __parse(klass_str).build_schema
  end

  def __parse_nested(klass_str)
    __parse(klass_str).tap { |visitor|
      visitor.root_key = visitor.root_key_for_collection = visitor.root_key_proc = visitor.key_transformer = nil
    }.build_schema
  end

  def __parse(klass_str)
    is_collection, klass_str = Rage::OpenAPI.__try_parse_collection(klass_str)

    klass = @namespace.const_get(klass_str)
    source_path, _ = Object.const_source_location(klass.name)
    ast = Prism.parse_file(source_path)

    visitor = Visitor.new(self, is_collection)
    ast.value.accept(visitor)

    visitor
  end

  class VisitorContext
    attr_accessor :symbols, :hashes, :keywords, :consts, :nil

    def initialize
      @symbols = []
      @hashes = []
      @keywords = {}
      @consts = []
      @nil = false
    end
  end

  class Visitor < Prism::Visitor
    attr_accessor :schema, :root_key, :root_key_for_collection, :root_key_proc, :key_transformer, :collection_key, :meta

    def initialize(parser, is_collection)
      @parser = parser
      @is_collection = is_collection

      @schema = {}
      @segment = @schema
      @context = nil
      @prev_contexts = []

      @self_name = nil
      @root_key = nil
      @root_key_for_collection = nil
      @root_key_proc = nil
      @key_transformer = nil
      @collection_key = false
      @meta = {}
    end

    def visit_class_node(node)
      @self_name ||= node.name.to_s

      if node.name =~ /Resource$|Serializer$/ && node.superclass
        visitor = @parser.__parse(node.superclass.name)
        @root_key, @root_key_for_collection, @root_key_proc = visitor.root_key, visitor.root_key_for_collection, visitor.root_key_proc
        @key_transformer, @collection_key, @meta = visitor.key_transformer, visitor.collection_key, visitor.meta
        @schema.merge!(visitor.schema)
      end

      super
    end

    def build_schema
      result = { "type" => "object" }

      result["properties"] = @schema if @schema.any?

      if @root_key_proc
        dynamic_root_key, dynamic_root_key_for_collection = @root_key_proc.call(@self_name)

        @root_key = dynamic_root_key
        @root_key_for_collection = dynamic_root_key_for_collection
      end

      if @is_collection
        result = if @collection_key && @root_key_for_collection
          { "type" => "object", "properties" => { @root_key_for_collection => { "type" => "object", "additionalProperties" => result }, **@meta } }
        elsif @collection_key
          { "type" => "object", "additionalProperties" => result }
        elsif @root_key_for_collection
          { "type" => "object", "properties" => { @root_key_for_collection => { "type" => "array", "items" => result }, **@meta } }
        else
          { "type" => "array", "items" => result }
        end
      elsif @root_key
        result = { "type" => "object", "properties" => { @root_key => result, **@meta } }
      end

      result = deep_transform_keys(result) if @key_transformer

      result
    end

    def visit_call_node(node)
      case node.name
      when :root_key
        @root_key_proc = nil
        context = with_context { visit(node.arguments) }
        @root_key, @root_key_for_collection = context.symbols

      when :attributes, :attribute
        context = with_context { visit(node.arguments) }
        context.symbols.each { |symbol| @segment[symbol] = { "type" => "string" } }
        context.keywords.except("if").each { |key, type| @segment[key] = get_type_definition(type) }

      when :nested, :nested_attribute
        context = with_context { visit(node.arguments) }
        with_inner_segment(context.symbols[0]) { visit(node.block) }

      when :meta
        context = with_context do
          visit(node.arguments)
          visit(node.block)
        end

        key = context.symbols[0] || "meta"
        unless context.nil
          @meta = { key => hash_to_openapi_schema(context.hashes[0]) }
        end

      when :many, :has_many, :one, :has_one, :association
        is_array = node.name == :many || node.name == :has_many
        context = with_context { visit(node.arguments) }
        association = context.symbols[0]
        key = context.keywords["key"] || association

        if node.block
          with_inner_segment(key, is_array:) { visit(node.block) }
        else
          resource = context.keywords["resource"] || (::Alba.inflector && "#{::Alba.inflector.classify(association.to_s)}Resource")
          is_valid_resource = @parser.namespace.const_get(resource) rescue false

          @segment[key] = if is_array
            @parser.__parse_nested(is_valid_resource ? "[#{resource}]" : "[Rage]") # TODO
          else
            @parser.__parse_nested(is_valid_resource ? resource : "Rage")
          end
        end

      when :transform_keys
        context = with_context { visit(node.arguments) }
        @key_transformer = get_key_transformer(context.symbols[0])

      when :collection_key
        @collection_key = true

      when :root_key!
        if (inflector = ::Alba.inflector)
          @root_key, @root_key_for_collection = nil

          @root_key_proc = ->(resource_name) do
            suffix = resource_name.end_with?("Resource") ? "Resource" : "Serializer"
            name = inflector.demodulize(resource_name).delete_suffix(suffix)

            inflector.underscore(name).yield_self { |key| [key, inflector.pluralize(key)] }
          end
        end
      end
    end

    def visit_hash_node(node)
      parsed_hash = YAML.safe_load(node.slice) rescue nil
      @context.hashes << parsed_hash if parsed_hash
    end

    def visit_assoc_node(node)
      value = case node.value
      when Prism::StringNode
        node.value.content
      when Prism::ArrayNode
        context = with_context { visit(node.value) }
        context.symbols[0] || context.consts[0]
      else
        node.value.slice
      end

      @context.keywords[node.key.value] = value
    end

    def visit_constant_read_node(node)
      return unless @context
      @context.consts << node.name.to_s
    end

    def visit_symbol_node(node)
      @context.symbols << node.value
    end

    def visit_nil_node(node)
      @context.nil = true
    end

    private

    def with_inner_segment(key, is_array: false)
      prev_segment = @segment

      properties = {}
      if is_array
        @segment[key] = { "type" => "array", "items" => { "type" => "object", "properties" => properties } }
      else
        @segment[key] = { "type" => "object", "properties" => properties }
      end
      @segment = properties

      yield
      @segment = prev_segment
    end

    def with_context
      @prev_contexts << @context if @context
      @context = VisitorContext.new
      yield
      current_context = @context
      @context = @prev_contexts.pop
      current_context
    end

    def hash_to_openapi_schema(hash)
      return { "type" => "object" } unless hash

      schema = hash.each_with_object({}) do |(key, value), memo|
        memo[key.to_s] = if value.is_a?(Hash)
          hash_to_openapi_schema(value)
        elsif value.is_a?(Array)
          { "type" => "array", "items" => { "type" => "string" } }
        else
          { "type" => "string" }
        end
      end

      { "type" => "object", "properties" => schema }
    end

    def deep_transform_keys(schema)
      schema.each_with_object({}) do |(key, value), memo|
        transformed_key = %w(type properties items additionalProperties).include?(key) ? key : @key_transformer.call(key)
        memo[transformed_key] = value.is_a?(Hash) ? deep_transform_keys(value) : value
      end
    end

    def get_key_transformer(transformer_id)
      return nil unless ::Alba.inflector

      case transformer_id
      when "camel"
        ->(key) { ::Alba.inflector.camelize(key) }
      when "lower_camel"
        ->(key) { ::Alba.inflector.camelize_lower(key) }
      when "dash"
        ->(key) { ::Alba.inflector.dasherize(key) }
      when "snake"
        ->(key) { ::Alba.inflector.underscore(key) }
      end
    end

    def get_type_definition(type_id)
      Rage::OpenAPI.__type_to_spec(type_id.delete_prefix(":"), default: true)
    end
  end
end
