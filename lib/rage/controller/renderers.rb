# frozen_string_literal: true

##
# This module overloads the `render` method on {RageController::API RageController::API} to enable the usage of custom renderers defined using {Rage::Configuration#renderer}.
#
module RageController::Renderers
  # @private
  def self.prepended(_)
    @__renderers = {}
  end

  # @private
  # rubocop:disable Layout/IndentationWidth, Layout/EndAlignment, Layout/HeredocIndentation
  def self.__register(name, block)
    @__renderers[name] = Rage::Internal.define_dynamic_method(self, block)

    render_args = @__renderers.keys.map { |key| "#{key}: nil" }.join(", ")

    class_eval <<~RUBY, __FILE__, __LINE__ + 1
      def render(#{render_args}, status: nil, **)
        raise "Render was called multiple times in this action." if @__rendered

        active_renderers = []
        #{@__renderers.keys.map { |key| "active_renderers << :#{key} if #{key}" }.join("\n")}

        return super(status:, **) if active_renderers.empty?

        if active_renderers.size > 1
          raise Rage::Errors::AmbiguousRenderError, "Only one renderer can be used per 'render' call, but multiple were provided: \#{active_renderers.join(", ")}"
        end

        result = case active_renderers.first
          #{@__renderers.map do |renderer_name, method_name|
            <<~RUBY
              when :#{renderer_name}
                #{method_name}(#{renderer_name}, **)
            RUBY
          end.join("\n")}
        end

        return if @__rendered
        render plain: result.to_s, status: (status || 200)
      end
    RUBY
  end
  # rubocop:enable all
end
