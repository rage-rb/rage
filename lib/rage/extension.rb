# frozen_string_literal: true

# @private
# This needs much more work to make it public, but it's already enough for inertia-rage.
class Rage::Extension
  class << self
    def initializer(id = name, before: nil, after: nil, &block)
      __initializers[id] << block
    end

    def configure(&block)
      __configurations << block
    end

    def __initializers
      @@initializers ||= Hash.new { |h, k| h[k] = [] }
    end

    def __configurations
      @@configurations ||= []
    end
  end
end
