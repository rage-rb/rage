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
    attr_accessor :symbols, :keywords, :strings

    def initialize
      @symbols = []
      @strings = []
      @keywords = {}
    end
  end

  class Visitor < Prism::Visitor
    attr_accessor :schema

    def initialize(parser, is_collection)
      @parser = parser
      @is_collection = is_collection

      @context = nil
      @schema = {}
      @segment = @schema
      @identifier = {}
    end

    def build_schema
      result = { "type" => "object" }

      properties = {}
      properties.merge!(@identifier)
      properties.merge!(@schema.sort.to_h)

      result["properties"] = properties if properties.any?
      result = { "type" => "array", "items" => result } if @is_collection
      result
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

    private

    def with_context
      @context = VisitorContext.new
      yield
      @context
    end
  end
end
