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
    is_collection, klass_str, serializer_args = Rage::OpenAPI.__parse_serializer_args(klass_str)

    klass = @namespace.const_get(klass_str)
    source_path, _ = Object.const_source_location(klass.name)
    ast = Prism.parse_file(source_path)

    visitor = Visitor.new(self, is_collection, serializer_args)
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
    attr_accessor :schema, :identifier

    def initialize(parser, is_collection, serializer_args)
      @parser = parser
      @is_collection = is_collection
      @serializer_args = serializer_args

      @context = nil
      @schema = {}
      @segment = @schema
      @identifier = {}

      @fields_by_view = {}
      @include_views = []
      @exclude_views = []
    end

    def build_schema
      result = { "type" => "object" }

      properties = {}
      properties.merge!(@identifier)
      properties.merge!(@schema.sort.to_h)

      result["properties"] = properties if properties.any?

      if @serializer_args.key?(:view)
        requested_view = @serializer_args[:view].to_s
        allowed_views = @include_views.map(&:to_s) + [requested_view]

        @fields_by_view.each do |field, view|
          result["properties"].delete(field.to_s) unless allowed_views.include?(view)
        end

        @exclude_views.each { |field| result["properties"].delete(field.to_s) }
      end

      result = { "type" => "array", "items" => result } if @is_collection
      result
    end

    def visit_class_node(node)
      if node.superclass && node.superclass.full_name != "Blueprinter::Base"
        visitor = @parser.__parse(node.superclass.name.to_s)
        @identifier.merge!(visitor.identifier)
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

      when :view
        return unless @serializer_args.any?

        context = with_context { visit(node.block) }
        context.symbols.each do |symbol|
          @fields_by_view[symbol] = node.arguments.arguments.first.unescaped
        end

      when :include_view, :include_views
        context = with_context { visit(node.arguments) }
        @include_views.concat(context.symbols.flatten)

      when :exclude, :excludes
        context = with_context { visit(node.arguments) }
        @exclude_views.concat(context.symbols.flatten)
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
