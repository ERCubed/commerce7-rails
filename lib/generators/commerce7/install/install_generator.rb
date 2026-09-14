# frozen_string_literal: true

require "rails/generators"
require "rails/generators/active_record"

module Commerce7
  module Generators
    # `rails generate commerce7:install` — scaffolds the migration and
    # initializer a fresh host app needs to start using this gem. Doesn't
    # touch an existing `tenants` table if the host already has one; review
    # and adapt the generated migration in that case instead of running it
    # as-is.
    class InstallGenerator < Rails::Generators::Base
      include Rails::Generators::Migration

      source_root File.expand_path("templates", __dir__)

      def self.next_migration_number(dirname)
        ActiveRecord::Generators::Base.next_migration_number(dirname)
      end

      def create_migration_file
        migration_template "create_tenants.rb.erb", "db/migrate/create_tenants.rb"
      end

      def create_initializer
        template "commerce7.rb", "config/initializers/commerce7.rb"
      end

      def show_readme
        readme "POST_INSTALL.md" if behavior == :invoke
      end
    end
  end
end
