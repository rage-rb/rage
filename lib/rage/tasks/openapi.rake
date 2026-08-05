namespace :openapi do
  task :validate do
    Rage::OpenAPI.build

    if Rage::OpenAPI.__warnings.any?
      puts "OpenAPI validation failed. Warnings: #{Rage::OpenAPI.__warnings}"
      exit 1
    else
      puts "OpenAPI validation passed without warnings."
    end
  end
end
