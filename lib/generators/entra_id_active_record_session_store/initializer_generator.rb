module EntraIdActiveRecordSessionStore
  module Generators
    class InitializerGenerator < Rails::Generators::Base
      desc 'Create an initializer to set the session store to EntraIdActiveRecordSessionStore.'

      source_root File.expand_path('templates', __dir__)

      def create_sessions_migration
        template 'initializer.rb', Rails.root.join('config', 'initializers', 'session_store.rb')
      end
    end
  end
end
