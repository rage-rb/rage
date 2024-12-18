# frozen_string_literal: true

class Rage::OpenAPI::Parsers::Request
  AVAILABLE_PARSERS = [
    Rage::OpenAPI::Parsers::SharedReference,
    Rage::OpenAPI::Parsers::YAML,
    Rage::OpenAPI::Parsers::Ext::ActiveRecord
  ]

  def self.parse(request_tag, namespace:)
    parser = AVAILABLE_PARSERS.find do |parser_class|
      parser = parser_class.new(namespace:)
      break parser if parser.known_definition?(request_tag)
    end

    parser.parse(request_tag) if parser
  end
end
