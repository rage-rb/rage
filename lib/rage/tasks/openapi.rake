namespace :openapi do
  task :validate do
    Rage.openapi.build

    if Rage.openapi.__warnings.any?
      puts "OpenAPI validation failed. Warnings: #{Rage.openapi.__warnings}"
      exit 1
    else
      puts "OpenAPI validation passed without warnings."
    end
  end
end
