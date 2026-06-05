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
    visitor = __parse(klass_str)
    visitor.build_schema
  end

  def __parse(klass_str)
    is_collection, klass_str, _ = Rage::OpenAPI.__parse_serializer_args(klass_str)

    klass = @namespace.const_get(klass_str)
    source_path, _ = Object.const_source_location(klass.name)
    ast = Prism.parse_file(source_path)

    visitor = Visitor.new(self, is_collection)
    ast.value.accept(visitor)

    visitor
  end

  class VisitorContext
    attr_accessor :symbols, :keywords, :strings, :consts

    def initialize
      @symbols = []
      @strings = []
      @keywords = {}
      @consts = nil
    end
  end

  class Visitor < Prism::Visitor
    attr_accessor :schema, :identifier, :key_transformer

    def initialize(parser, is_collection)
      @parser = parser
      @is_collection = is_collection

      @context = nil
      @schema = {}
      @segment = @schema
      @identifier = {}

      @key_transformer = nil
    end

    def build_schema
      result = { "type" => "object" }

      properties = {}
      properties.merge!(@identifier)
      properties.merge!(@schema.sort.to_h)

      result["properties"] = properties if properties.any?
      result = { "type" => "array", "items" => result } if @is_collection

      result = deep_transform_keys(result) if @key_transformer

      result
    end

    def visit_class_node(node)
      if node.superclass && node.superclass.full_name != "Blueprinter::Base"
        visitor = @parser.__parse(node.superclass.name.to_s)
        @identifier.merge!(visitor.identifier)
        @key_transformer = visitor.key_transformer
        @schema.merge!(visitor.schema)
      end

      super
    end

    def visit_call_node(node)
      case node.name
      when :identifier
        context = with_context { visit(node.arguments) }
        @identifier[context.symbols.first] = { "type" => "string" }

      when :fields, :field
        context = with_context { visit(node.arguments) }

        if context.keywords["name"]
          @segment[context.keywords["name"]] = { "type" => "string" }
        elsif node.block
          @segment[context.symbols.first] = { "type" => "string" } if context.symbols.first
          @segment[context.strings.first] = { "type" => "string" } if context.strings.first
        else
          context.symbols.each { |symbol| @segment[symbol] = { "type" => "string" } }
          context.strings.each { |string| @segment[string] = { "type" => "string" } }
        end

      when :transform
        context = with_context { visit(node.arguments) }
        @key_transformer ||= get_key_transformer(context.consts)
      end
    end

    def visit_assoc_node(node)
      @context.keywords[node.key.value] = node.value.unescaped
    end

    def visit_symbol_node(node)
      @context.symbols << node.value
    end

    def visit_string_node(node)
      @context.strings << node.unescaped
    end

    def visit_constant_read_node(node)
      return unless @context
      @context.consts = node.name.to_s
    end

    private

    def with_context
      @context = VisitorContext.new
      yield
      @context
    end

    def deep_transform_keys(schema)
      schema.each_with_object({}) do |(key, value), memo|
        transformed_key = %w(type properties items additionalProperties).include?(key) ? key : @key_transformer.call(key)
        memo[transformed_key] = value.is_a?(Hash) ? deep_transform_keys(value) : value
      end
    end

    def get_key_transformer(transformer_class)
      return nil unless defined?(ActiveSupport)

      case transformer_class
      when "LowerCamelTransformer"
        ->(key) { key.to_s.camelize(:lower) }
      when "CamelTransformer"
        ->(key) { key.to_s.camelize }
      when "DashTransformer"
        ->(key) { key.to_s.dasherize }
      end
    end
  end
end
