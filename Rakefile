# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

task default: :spec

task :appraise do |_, args|
  ext_versions = `appraisal list`.split("\n")

  # Since we want to test against the main branch separately, we remove it from the list.
  ext_versions.reject! { |version| version.end_with?("_head") }

  ext_versions.each do |ext_version|
    puts ">> Appraising #{ext_version}"

    gem_name = ext_version.sub(/_\d+(_\d+)*$/, "")
    system "bundle exec appraisal #{ext_version} rspec spec/ext/#{gem_name}/"
  end
end
