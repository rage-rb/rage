namespace :openapi do
  desc "Validate OpenAPI tags and fail if any warnings were produced"
  task :validate do
    abort "OpenAPI validation requires a booted application." unless Rage.config.internal.initialized?

    warnings = Rage::OpenAPI.__collect_warnings { Rage::OpenAPI.build }

    if warnings.any?
      abort "OpenAPI validation failed with #{warnings.size} warning(s)."
    else
      puts "OpenAPI validation passed without warnings."
    end
  end
end
