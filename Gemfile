# frozen_string_literal: true

source "https://rubygems.org"

gemspec

group :development, :test do
  # Faraday's :json response middleware is incompatible with the json 3.x
  # gem bundled with recent Ruby versions (raises ArgumentError deep inside
  # JSON.parse) — pin to the 2.x line Faraday actually supports.
  gem "json", "~> 2.9"

  gem "sqlite3", ">= 2.1"
  gem "combustion", "~> 1.5"
  gem "rspec-rails"
  gem "webmock"

  gem "bundler-audit", require: false
  gem "brakeman", require: false
  gem "rubocop-rails-omakase", require: false
end
