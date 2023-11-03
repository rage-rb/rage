# frozen_string_literal: true

require_relative "lib/rage/version"

Gem::Specification.new do |spec|
  spec.name = "rage-rb"
  spec.version = Rage::VERSION
  spec.authors = ["Roman Samoilov"]
  spec.email = ["rsamoi@icloud.com"]

  spec.summary = "Fast web framework compatible with Rails."
  spec.homepage = "https://github.com/rage-rb/rage"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/rage-rb/rage"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) || f.start_with?(*%w[bin/ test/ spec/ features/ .git .circleci appveyor])
    end
  end
  spec.bindir = "exe"
  spec.executables = ["rage"]
  spec.require_paths = ["lib"]

  spec.add_dependency "thor", "~> 1.0"
  spec.add_dependency "rack", "~> 2.0"
  spec.add_dependency "rage-iodine", "2.1.0"
end
