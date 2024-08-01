require_relative 'lib/entra_id_active_record_session_store/version'

Gem::Specification.new do |s|
  s.name    = 'entra_id_active_record_session_store'
  s.version = EntraIdActiveRecordSessionStore::VERSION
  s.authors = ['David Susco']
  s.email   = ['dsusco@clarku.edu']

  s.summary     = 'A subclass of Active Record Session Store that tracks sessionindexes for single logout.'
  s.description = s.summary
  s.homepage    = 'https://github.com/dsusco/entra_id_active_record_session_store'
  s.license     = 'MIT'

  s.required_ruby_version = '>= 3.0.0'

  s.metadata = {
    'bug_tracker_uri'   => "#{s.homepage}/issues",
    'changelog_uri'     => "#{s.homepage}/releases/tag/v#{s.version}",
    'homepage_uri'      => s.homepage,
    'source_code_uri'   => s.homepage
  }

  s.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir['{lib}/**/*', 'MIT-LICENSE', 'Rakefile', 'README.md']
  end

  s.add_dependency 'activerecord-session_store', '~> 2.0'
  s.add_dependency 'rack_entra_id_auth', '~> 1.0'

  s.add_development_dependency 'minitest', '~> 5.16'
  s.add_development_dependency 'rake', '~> 13.0'
  s.add_development_dependency 'rubocop', '~> 1.21'
end
