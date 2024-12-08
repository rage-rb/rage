# frozen_string_literal: true

class Rage::OpenAPI::Parsers::SharedReference
  def initialize(**)
  end

  def known_definition?(str)
    str.start_with?("#/components")
  end

  def parse(component_path)
    { "$ref" => component_path } if valid_components_ref?(component_path)
  end

  private

  def valid_components_ref?(component_path)
    shared_components = Rage::OpenAPI.__shared_components
    return false if shared_components.empty?

    !!component_path[2..].split("/").reduce(shared_components) do |components, component_key|
      components[component_key] if components
    end
  end
end
