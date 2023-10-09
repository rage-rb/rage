# frozen_string_literal: true

class Rage::Router::Strategies::Via
  attr_reader :name, :must_match_when_derived

  ALLOWED_VIA_METHODS = %w[get post put patch delete all].freeze

  def initialize
    @name = "via"
    @must_match_when_derived = false
  end

  def custom?
    false
  end

  def storage
    ViaStorage.new
  end

  def validate(value)
    raise 'Via should be a string or an array of strings' if !value.is_a?(String) && !value.is_a?(Array)

    [value].flatten.each do |method|
      raise "Via method '#{method}' is not allowed" unless ALLOWED_VIA_METHODS.include?(method)
    end
  end

  class ViaStorage
    def initialize
      @methods = []
    end

    def get(method)
      # TODO: implement this
      # @methods.include?(method) ? method : nil
    end

    def set(method, _value)
      # TODO: implement this

      # @methods << method
      # @methods.flatten!
    end

  end
end
