# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in rage.gemspec
gemspec

gem "rake", "~> 13.0"

gem "rspec", "~> 3.0"
gem "yard"
gem "rubocop", "~> 1.65", require: false

group :test do
  gem "http"
  gem "pg"
  gem "mysql2"
  gem "connection_pool", "~> 2.0"
  gem "rbnacl"
  gem "domain_name"
  gem "websocket-client-simple"
end
