# frozen_string_literal: true

class Rage::Router::Strategies::Host
  attr_reader :name, :must_match_when_derived

  def initialize
    @name = "host"
    @must_match_when_derived = false
  end

  def storage
    HostStorage.new
  end

  def custom?
    false
  end

  def validate(value)
    if !value.is_a?(String) && !value.is_a?(Regexp)
      raise ArgumentError, "Host should be a string or a Regexp"
    end
  end

  class HostStorage
    def initialize
      @hosts = {}
      @regexp_hosts = []
    end

    def get(host)
      exact = @hosts[host]
      return exact if exact

      @regexp_hosts.each do |regexp|
        return regexp[:value] if regexp[:host] =~ host.to_s
      end

      nil
    end

    def set(host, value)
      if host.is_a?(Regexp)
        @regexp_hosts << { host: host, value: value }
      else
        @hosts[host] = value
      end
    end
  end
end
