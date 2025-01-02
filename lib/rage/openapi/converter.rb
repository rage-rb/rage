# frozen_string_literal: true

class Rage::OpenAPI::Converter
  def initialize(nodes)
    @nodes = nodes
    @used_tags = Set.new
    @used_security_schemes = Set.new

    @spec = {
      "openapi" => "3.0.0",
      "info" => {},
      "components" => {},
      "tags" => [],
      "paths" => {}
    }
  end

  def run
    @spec["info"] = {
      "version" => @nodes.version || "1.0.0",
      "title" => @nodes.title || build_app_name
    }

    @spec["paths"] = @nodes.leaves.each_with_object({}) do |node, memo|
      next if node.private || node.parents.any?(&:private)

      path_parameters = []
      path = node.http_path.gsub(/:(\w+)/) do
        path_parameters << $1
        "{#{$1}}"
      end

      unless memo.key?(path)
        memo[path] = {}
        path_parameters.each do |parameter|
          (memo[path]["parameters"] ||= []) << {
            "in" => "path",
            "name" => parameter,
            "required" => true,
            "schema" => { "type" => parameter.end_with?("id") ? "integer" : "string" }
          }
        end
      end

      method = node.http_method.downcase
      memo[path][method] = {
        "summary" => node.summary || "",
        "description" => node.description&.join(" ") || "",
        "deprecated" => !!(node.deprecated || node.parents.any?(&:deprecated)),
        "security" => build_security(node),
        "tags" => build_tags(node)
      }

      responses = node.parents.reverse.map(&:responses).reduce(&:merge).merge(node.responses)

      memo[path][method]["responses"] = if responses.any?
        responses.each_with_object({}) do |(status, response), memo|
          memo[status] = if response.nil?
            { "description" => "" }
          elsif response.key?("$ref") && response["$ref"].start_with?("#/components/responses")
            response
          else
            { "description" => "", "content" => { "application/json" => { "schema" => response } } }
          end
        end
      else
        { "200" => { "description" => "" } }
      end

      if node.request
        if node.request.key?("$ref") && node.request["$ref"].start_with?("#/components/requestBodies")
          memo[path][method]["requestBody"] = node.request
        else
          memo[path][method]["requestBody"] = { "content" => { "application/json" => { "schema" => node.request } } }
        end
      end
    end

    if @used_security_schemes.any?
      @spec["components"]["securitySchemes"] = @used_security_schemes.each_with_object({}) do |auth_entry, memo|
        memo[auth_entry[:name]] = auth_entry[:definition]
      end
    end

    if (shared_components = Rage::OpenAPI.__shared_components["components"])
      shared_components.each do |definition_type, definitions|
        (@spec["components"][definition_type] ||= {}).merge!(definitions)
      end
    end

    @spec["tags"] = @used_tags.sort.map { |tag| { "name" => tag } }

    @spec
  end

  private

  def build_app_name
    basename = Rage.root.basename.to_s
    basename.capitalize.gsub(/[\s\-_]([a-zA-Z0-9]+)/) { " #{$1.capitalize}" }
  end

  def build_security(node)
    available_before_actions = node.controller.__before_actions_for(node.action.to_sym)

    node.auth.filter_map do |auth_entry|
      if available_before_actions.any? { |action_entry| action_entry[:name] == auth_entry[:method].to_sym }
        auth_name = auth_entry[:name].gsub(/[^A-Za-z0-9\-._]/, "")
        @used_security_schemes << auth_entry.merge(name: auth_name)

        { auth_name => [] }
      end
    end
  end

  def build_tags(node)
    controller_name = node.controller.name.sub(/Controller$/, "")
    namespace_i = controller_name.rindex("::")

    if namespace_i
      module_name, class_name = controller_name[0...namespace_i], controller_name[namespace_i + 2..]
    else
      module_name, class_name = "", controller_name
    end

    tag = if module_name =~ /::(V\d+)/
      "#{$1.downcase}/#{class_name}"
    else
      class_name
    end

    if (custom_tag_resolver = Rage.config.openapi.tag_resolver)
      tag = custom_tag_resolver.call(node.controller, node.action.to_sym, tag)
    end

    Array(tag).tap do |node_tags|
      @used_tags += node_tags
    end
  end
end
