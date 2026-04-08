# frozen_string_literal: true

class Rage::OpenAPI::Parsers::Ext::Blueprinter
  attr_reader :namespace

  def initialize(namespace: Object, **)
    @namespace = namespace
    @parsing_stack = []
  end

  def known_definition?(str)
    _, str = Rage::OpenAPI.__try_parse_collection(str)
    defined?(Blueprinter::Base) && @namespace.const_get(str).ancestors.include?(Blueprinter::Base)
  rescue NameError
    false
  end

  def parse(klass_str, view: :default)
    __parse(klass_str, view:).build_schema
  end

  def __parse_nested(klass_str)
    return { "type" => "object" } if @parsing_stack.include?(klass_str)
    __parse(klass_str).build_schema
  end

  def __parse(klass_str, view: :default)
    is_collection, klass_str = Rage::OpenAPI.__try_parse_collection(klass_str)

    klass = @namespace.const_get(klass_str)
    source_path, _ = Object.const_source_location(klass.name)
    ast = Prism.parse_file(source_path)

    @parsing_stack.push(klass_str)
    visitor = Visitor.new(self, is_collection, klass_str, view)
    ast.value.accept(visitor)
    @parsing_stack.pop

    visitor
  end

  class Visitor < Prism::Visitor
    attr_accessor :schema

    def initialize(parser, is_collection, target_class_name, view)
      @parser = parser
      @is_collection = is_collection
      @target_class_name = target_class_name
      @view = view
      @schema = {}
      @current_segment = @schema
      @current_class_name = nil
      @current_view = :default
    end

    def build_schema
      result = { "type" => "object" }
      result["properties"] = @schema if @schema.any?

      if @is_collection
        result = { "type" => "array", "items" => result }
      end

      result
    end

    def visit_class_node(node)
      previous_class = @current_class_name
      @current_class_name = node.constant_path.slice
      super
      @current_class_name = previous_class
    end

    def visit_call_node(node)
      return super unless @current_class_name == @target_class_name

      case node.name
      when :field, :identifier
        # Only add field if we are in the requested view
        return unless @current_view == :default || @current_view == @view

        first_arg = node.arguments&.arguments&.first
        if first_arg.is_a?(Prism::SymbolNode)
          field_name = first_arg.value.to_s
          @current_segment[field_name] = { "type" => "string" }
        end

      when :association
        return unless @current_view == :default || @current_view == @view

        first_arg = node.arguments&.arguments&.first
        if first_arg.is_a?(Prism::SymbolNode)
          association_name = first_arg.value.to_s

          blueprint_klass_str = nil
          node.arguments&.arguments&.each do |arg|
            if arg.is_a?(Prism::KeywordHashNode)
              arg.elements.each do |assoc|
                if assoc.key.value == "blueprint"
                  blueprint_klass_str = assoc.value.slice
                end
              end
            end
          end

          @current_segment[association_name] = if blueprint_klass_str
            @parser.__parse_nested(blueprint_klass_str)
          else
            { "type" => "object" }
          end
        end

      when :view
        # Get the view name from the first argument
        first_arg = node.arguments&.arguments&.first
        if first_arg.is_a?(Prism::SymbolNode)
          view_name = first_arg.value.to_sym
          previous_view = @current_view
          @current_view = view_name
          # Visit the block contents
          visit(node.block)
          @current_view = previous_view
        end

      else
        super
      end
    end
  end
end