# frozen_string_literal: true

module Rage::CLI
  class OpenAPI < Base
    desc "validate", "Validate OpenAPI tags and fail if any warnings were produced"
    def validate
      environment

      abort "OpenAPI validation requires a booted application." unless Rage.config.internal.initialized?

      warnings = Rage::OpenAPI.__collect_warnings { Rage::OpenAPI.build }

      if warnings.any?
        abort "#{set_color("𐄂", :red, :bold)} OpenAPI validation failed with #{warnings.size} warning(s)."
      else
        say "#{set_color("✓", :green, :bold)} OpenAPI validation passed without warnings."
      end
    end
  end
end
