# frozen_string_literal: true

require "erb"
require "yaml"

if !defined?(Prism)
  fail <<~ERR

    rage-rb depends on Prism to build OpenAPI specifications. Add the following line to your Gemfile:
    gem "prism"

  ERR
end

module Rage::OpenAPI
  # Create a new OpenAPI application.
  #
  # @param namespace [String, Module] limit the parser to a specific namespace
  # @example
  #   map "/publicapi" do
  #     run Rage.openapi.application
  #   end
  # @example
  #   map "/publicapi/v1" do
  #     run Rage.openapi.application(namespace: "Api::V1")
  #   end
  #
  #   map "/publicapi/v2" do
  #     run Rage.openapi.application(namespace: "Api::V2")
  #   end
  def self.application(namespace: nil)
    html_app = ->(env) do
      __data_cache[[:page, namespace]] ||= begin
        scheme, host, path = env["rack.url_scheme"], env["HTTP_HOST"], env["SCRIPT_NAME"]
        spec_url = "#{scheme}://#{host}#{path}/json"
        page = ERB.new(File.read("#{__dir__}/index.html.erb")).result(binding)

        [200, { "Content-Type" => "text/html; charset=UTF-8" }, [page]]
      end
    end

    json_app = ->(env) do
      spec = (__data_cache[[:spec, namespace]] ||= build(namespace:).to_json)
      [200, { "Content-Type" => "application/json" }, [spec]]
    end

    app = ->(env) do
      if env["PATH_INFO"] == ""
        html_app.call(env)
      elsif env["PATH_INFO"] == "/json"
        json_app.call(env)
      else
        [404, {}, ["Not Found"]]
      end
    end

    if Rage.config.middleware.include?(Rage::Reloader)
      Rage.with_middlewares(app, [Rage::Reloader])
    elsif defined?(ActionDispatch::Reloader) && Rage.config.middleware.include?(ActionDispatch::Reloader)
      Rage.with_middlewares(app, [ActionDispatch::Reloader])
    else
      app
    end
  end

  # Build an OpenAPI specification for the application.
  # @param namespace [String, Module] limit the parser to a specific namespace
  # @return [Hash]
  def self.build(namespace: nil)
    Builder.new(namespace:).run
  end

  # @private
  def self.__shared_components
    __data_cache[:shared_components] ||= begin
      components_file = Rage.root.join("config").glob("openapi_components.*")[0]

      if components_file.nil?
        {}
      else
        case components_file.extname
        when ".yml", ".yaml"
          YAML.safe_load(components_file.read)
        when ".json"
          JSON.parse(components_file.read)
        else
          Rage::OpenAPI.__log_warn "unrecognized file extension: #{components_file.relative_path_from(Rage.root)}; expected either .yml or .json"
          {}
        end
      end
    end
  end

  # @private
  def self.__data_cache
    @__data_cache ||= {}
  end

  # @private
  def self.__reset_data_cache
    __data_cache.clear
  end

  # @private
  def self.__try_parse_collection(str)
    if str =~ /^Array<([\w\s:\(\)]+)>$/ || str =~ /^\[([\w\s:\(\)]+)\]$/
      [true, $1]
    else
      [false, str]
    end
  end

  # @private
  def self.__module_parent(klass)
    klass.name =~ /::[^:]+\z/ ? Object.const_get($`) : Object
  rescue NameError
    Object
  end

  # @private
  def self.__log_warn(log)
    puts "WARNING: #{log}"
  end

  module Nodes
  end

  module Parsers
    module Ext
    end
  end
end

require_relative "builder"
require_relative "collector"
require_relative "parser"
require_relative "converter"
require_relative "nodes/root"
require_relative "nodes/parent"
require_relative "nodes/method"
require_relative "parsers/ext/alba"
require_relative "parsers/ext/active_record"
require_relative "parsers/yaml"
require_relative "parsers/shared_reference"
require_relative "parsers/request"
require_relative "parsers/response"
