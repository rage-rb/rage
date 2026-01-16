# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

task default: :spec

task :appraise do |_, args|
  # Pulls all the Rails versions from the Appraisal file
  rails_versions = `appraisal list`.split("\n")
  # Since we want to test against the main branch separately,
  # we remove it from the list.
  rails_versions.delete("rails_main")

  rails_versions.each do |rails_version|
    puts ">> Appraising #{rails_version}"

    system("bundle exec appraisal #{rails_version} rspec spec/ext/*")
  end
end
