# frozen_string_literal: true

class Rage::OpenAPI::Parsers::Response
  AVAILABLE_PARSERS = [
    Rage::OpenAPI::Parsers::SharedReference,
    Rage::OpenAPI::Parsers::Ext::ActiveRecord,
    Rage::OpenAPI::Parsers::Ext::Alba,
    Rage::OpenAPI::Parsers::YAML
  ]

  def self.parse(response_tag, namespace:)
    parser = AVAILABLE_PARSERS.find do |parser_class|
      parser = parser_class.new(namespace:)
      break parser if parser.known_definition?(response_tag)
    end

    parser.parse(response_tag) if parser
  end
end
