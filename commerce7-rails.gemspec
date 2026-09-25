# frozen_string_literal: true

require_relative "lib/commerce7/version"

Gem::Specification.new do |s|
  s.name        = "commerce7-rails"
  s.version     = Commerce7::VERSION
  s.required_ruby_version = ">= 3.2"
  s.summary     = "Rails building blocks for Commerce7 App Store integrations"
  s.description = "Activation/deactivation lifecycle, webhook dispatch, App Extension staff-JWT " \
                   "auth, the Commerce7 REST client, and the post-uninstall data purge Commerce7's " \
                   "security review requires — configured once, reused across every Commerce7 app."
  s.authors     = [ "Eric Roberts" ]
  s.license     = "MIT"
  s.homepage    = "https://github.com/ERCubed/commerce7-rails"

  s.metadata = {
    "homepage_uri" => s.homepage,
    "source_code_uri" => s.homepage,
    "rubygems_mfa_required" => "true"
  }

  s.files = Dir.chdir(__dir__) do
    Dir["lib/**/*", "app/**/*", "README.md", "LICENSE"].select { |f| File.file?(f) }
  end
  s.require_paths = [ "lib" ]

  # json 3.0 changed JSON.parse, and ActiveSupport before 8.1.4 (other than
  # 7.2) and Faraday before 2.14.4 call it in ways it no longer accepts, so
  # jsonb reads and REST client responses raise. See "Requirements" in the README.
  s.add_dependency "rails", ">= 8.1.4"
  s.add_dependency "faraday", ">= 2.14.4"
end
