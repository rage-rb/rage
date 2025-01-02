# frozen_string_literal: true

class Rage::OpenAPI::Parser
  def parse_dangling_comments(node, comments)
    i = 0

    while i < comments.length
      children = nil
      expression = comments[i].slice.delete_prefix("#").strip

      if expression =~ /@deprecated\b/
        if node.deprecated
          Rage::OpenAPI.__log_warn "duplicate @deprecated tag detected at #{location_msg(comments[i])}"
        else
          node.deprecated = true
        end
        children = find_children(comments[i + 1..])

      elsif expression =~ /@private\b/
        if node.private
          Rage::OpenAPI.__log_warn "duplicate @private tag detected at #{location_msg(comments[i])}"
        else
          node.private = true
        end
        children = find_children(comments[i + 1..])

      elsif expression =~ /@version\s/
        if node.root.version
          Rage::OpenAPI.__log_warn "duplicate @version tag detected at #{location_msg(comments[i])}"
        else
          node.root.version = expression[9..]
        end

      elsif expression =~ /@title\s/
        if node.root.title
          Rage::OpenAPI.__log_warn "duplicate @title tag detected at #{location_msg(comments[i])}"
        else
          node.root.title = expression[7..]
        end

      elsif expression =~ /@response\s/
        parse_response_tag(expression, node, comments[i])

      elsif expression =~ /@auth\s/
        method, name, tail_name = expression[6..].split(" ", 3)
        children = find_children(comments[i + 1..])

        if tail_name
          Rage::OpenAPI.__log_warn "incorrect `@auth` name detected at #{location_msg(comments[i])}; security scheme name cannot contain spaces"
        end

        auth_entry = {
          method:,
          name: name || method,
          definition: children.any? ? YAML.safe_load(children.join("\n")) : { "type" => "http", "scheme" => "bearer" }
        }

        if !node.controller.__before_action_exists?(method.to_sym)
          Rage::OpenAPI.__log_warn "referenced before action `#{method}` is not defined in #{node.controller} at #{location_msg(comments[i])}; ensure a corresponding `before_action` call exists"
        elsif node.auth.include?(auth_entry) || node.root.parent_nodes.any? { |parent_node| parent_node.auth.include?(auth_entry) }
          Rage::OpenAPI.__log_warn "duplicate @auth tag detected at #{location_msg(comments[i])}"
        else
          node.auth << auth_entry
        end
      end

      if children&.any?
        i += children.length + 1
      else
        i += 1
      end
    end
  end

  def parse_method_comments(node, comments)
    i = 0

    while i < comments.length
      children = nil
      expression = comments[i].slice.delete_prefix("#").strip

      if !expression.start_with?("@")
        if node.summary
          Rage::OpenAPI.__log_warn "invalid summary entry detected at #{location_msg(comments[i])}; summary should only be one line"
        else
          node.summary = expression
        end

      elsif expression =~ /@deprecated\b/
        if node.parents.any?(&:deprecated)
          Rage::OpenAPI.__log_warn "duplicate `@deprecated` tag detected at #{location_msg(comments[i])}; tag already exists in a parent class"
        else
          node.deprecated = true
        end
        children = find_children(comments[i + 1..])

      elsif expression =~ /@private\b/
        if node.parents.any?(&:private)
          Rage::OpenAPI.__log_warn "duplicate `@private` tag detected at #{location_msg(comments[i])}; tag already exists in a parent class"
        else
          node.private = true
        end
        children = find_children(comments[i + 1..])

      elsif expression =~ /@description\s/
        children = find_children(comments[i + 1..])
        node.description = [expression[13..]] + children

      elsif expression =~ /@response\s/
        parse_response_tag(expression, node, comments[i])

      elsif expression =~ /@request\s/
        request = expression[9..]
        if node.request
          Rage::OpenAPI.__log_warn "duplicate `@request` tag detected at #{location_msg(comments[i])}"
        else
          parsed = Rage::OpenAPI::Parsers::Request.parse(
            request,
            namespace: Rage::OpenAPI.__module_parent(node.controller)
          )

          if parsed
            node.request = parsed
          else
            Rage::OpenAPI.__log_warn "unrecognized `@request` tag detected at #{location_msg(comments[i])}"
          end
        end

      elsif expression =~ /@internal\b/
        # no-op
        children = find_children(comments[i + 1..])

      else
        Rage::OpenAPI.__log_warn "unrecognized `#{expression.split(" ")[0]}` tag detected at #{location_msg(comments[i])}"
      end

      if children&.any?
        i += children.length + 1
      else
        i += 1
      end
    end
  end

  private

  def find_children(comments)
    children = []

    comments.each do |comment|
      expression = comment.slice.sub(/^#\s/, "")

      if expression.start_with?(/\s{2}/)
        children << expression.strip
      elsif expression.start_with?("@")
        break
      else
        Rage::OpenAPI.__log_warn "unrecognized expression detected at #{location_msg(comment)}; use two spaces to mark multi-line expressions"
        break
      end
    end

    children
  end

  def location_msg(comment)
    location = comment.location
    relative_path = Pathname.new(location.__source_path).relative_path_from(Rage.root)

    "#{relative_path}:#{location.start_line}"
  end

  def parse_response_tag(expression, node, comment)
    response = expression[10..].strip
    status, response_data = if response =~ /^\d{3}$/
      [response, nil]
    elsif response =~ /^\d{3}/
      response.split(" ", 2)
    else
      ["200", response]
    end

    if node.responses.has_key?(status)
      Rage::OpenAPI.__log_warn "duplicate `@response` tag detected at #{location_msg(comment)}"
    elsif response_data.nil?
      node.responses[status] = nil
    else
      parsed = Rage::OpenAPI::Parsers::Response.parse(
        response_data,
        namespace: Rage::OpenAPI.__module_parent(node.controller)
      )

      if parsed
        node.responses[status] = parsed
      else
        Rage::OpenAPI.__log_warn "unrecognized `@response` tag detected at #{location_msg(comment)}"
      end
    end
  end
end
