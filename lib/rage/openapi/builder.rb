# frozen_string_literal: true

##
# Build OpenAPI specification for the app. Consists of three steps:
#
# * `Rage::OpenAPI::Builder` - build a tree of action nodes;
# * `Rage::OpenAPI::Parser` - parse OpenAPI tags and save the result into the nodes;
# * `Rage::OpenAPI::Converter` - convert the tree into an OpenAPI spec;
#
class Rage::OpenAPI::Builder
  class ParsingError < StandardError
  end

  def initialize(namespace: nil)
    @namespace = namespace.to_s if namespace

    @collectors_cache = {}
    @nodes = Rage::OpenAPI::Nodes::Root.new
    @routes = Rage.__router.routes.group_by { |route| route[:meta][:controller_class] }
  end

  def run
    parser = Rage::OpenAPI::Parser.new

    @routes.each do |controller, routes|
      next if skip_controller?(controller)

      parent_nodes = fetch_ancestors(controller).map do |klass|
        @nodes.new_parent_node(klass) { |node| parser.parse_dangling_comments(node, parse_class(klass).dangling_comments) }
      end

      routes.each do |route|
        action = route[:meta][:action]

        method_comments = fetch_ancestors(controller).filter_map { |klass|
          parse_class(klass).method_comments(action)
        }.first

        method_node = @nodes.new_method_node(controller, action, parent_nodes)
        method_node.http_method, method_node.http_path = route[:method], route[:path]

        parser.parse_method_comments(method_node, method_comments)
      end

    rescue ParsingError
      Rage::OpenAPI.__log_warn "skipping #{controller.name} because of parsing error"
      next
    end

    Rage::OpenAPI::Converter.new(@nodes).run
  end

  private

  def skip_controller?(controller)
    should_skip_controller = controller.nil? || !controller.ancestors.include?(RageController::API)
    should_skip_controller ||= !controller.name.start_with?(@namespace) if @namespace

    should_skip_controller
  end

  def fetch_ancestors(controller)
    controller.ancestors.take_while { |klass| klass != RageController::API }
  end

  def parse_class(klass)
    @collectors_cache[klass] ||= begin
      source_path, _ = Object.const_source_location(klass.name)
      ast = Prism.parse_file(source_path)

      raise ParsingError if ast.errors.any?

      # save the "comment => file" association
      ast.comments.each do |comment|
        comment.location.define_singleton_method(:__source_path) { source_path }
      end

      collector = Rage::OpenAPI::Collector.new(ast.comments)
      ast.value.accept(collector)

      collector
    end
  end
end
