$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

require 'erb'
require 'logger'
require 'stringio'
require 'zlib'
require 'base64'

require 'active_record'
require 'action_dispatch'
require 'rack/mock_request'

require 'entra_id_active_record_session_store'

require 'minitest/autorun'

# keep ruby-saml's and Active Record's output out of the test run
OneLogin::RubySaml::Logging.logger = Logger.new(nil)
ActiveRecord::Migration.verbose = false

ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: ':memory:')

module SessionStoreTestHelpers
  ACS_URL         = 'https://app.example.com/saml/login'.freeze
  SLO_SERVICE_URL = 'https://app.example.com/saml/logout'.freeze
  SESSION_KEY     = '_test_session'.freeze

  TEMPLATES = File.expand_path('../lib/generators/entra_id_active_record_session_store/templates', __dir__)

  # Renders the generator's migration template the way the generator would.
  class MigrationTemplate
    def migration_class_name = 'CreateSessions'
    def migration_version = "[#{ActiveRecord::Migration.current_version}]"
    def session_table_name = 'sessions'

    def render
      ERB.new(File.read(File.join(TEMPLATES, 'create_sessions_migration.rb'))).result(binding)
    end
  end

  def self.create_sessions_table!
    connection = ActiveRecord::Base.connection
    connection.drop_table(:sessions) if connection.table_exists?(:sessions)

    Object.send(:remove_const, :CreateSessions) if Object.const_defined?(:CreateSessions)
    eval(MigrationTemplate.new.render, TOPLEVEL_BINDING) # rubocop:disable Security/Eval
    CreateSessions.migrate(:up)

    ActiveRecord::SessionStore::Session.reset_column_information
  end

  def setup
    super
    RackEntraIdAuth.instance_variable_set(:@config, nil)
    RackEntraIdAuth.configure do |config|
      config.assertion_consumer_service_url = ACS_URL
      config.single_logout_service_url      = SLO_SERVICE_URL
    end

    SessionStoreTestHelpers.create_sessions_table!
    @cookies = {}
  end

  def teardown
    RackEntraIdAuth.instance_variable_set(:@config, nil)
    super
  end

  def session_class
    ActiveRecord::SessionStore::Session
  end

  # A Rack app behind the session store. The block gets the session and the
  # request, standing in for RackEntraIdAuth's middleware and the Rails app.
  def app (&block)
    inner = lambda do |env|
      request = Rack::Request.new(env)
      block&.call(env['rack.session'], request)
      [200, { 'content-type' => 'text/plain' }, ['ok']]
    end

    # ActionDispatch's session stores write their cookie through the cookie
    # jar, so ActionDispatch::Cookies has to sit in front, as it does in Rails
    ActionDispatch::Cookies.new(ActionDispatch::Session::EntraIdActiveRecordStore.new(inner, key: SESSION_KEY))
  end

  # Makes a request, sending and storing cookies like a browser would.
  def request (app, url, method: 'GET', params: nil)
    options = { method: method, 'rack.errors' => StringIO.new }
    options['HTTP_COOKIE'] = @cookies.map { |key, value| "#{key}=#{value}" }.join('; ') if @cookies.any?

    if params
      options[:input] = URI.encode_www_form(params)
      options['CONTENT_TYPE'] = 'application/x-www-form-urlencoded'
    end

    env = Rack::MockRequest.env_for(url, options)
    response = Rack::MockResponse[*app.call(env)]

    Array(response.headers['set-cookie']).flat_map { |header| header.split("\n") }.each do |cookie|
      key, value = cookie.split(';').first.split('=', 2)
      @cookies[key] = value
    end

    response
  end

  # Starts a new "browser", with no cookies.
  def clear_cookies
    @cookies = {}
  end

  # A base64-encoded SAML login response with the given sessionindex. The
  # signature is a placeholder: ruby-saml only reads elements from the signed
  # assertion, so the Signature element has to be there, but the store never
  # validates it (that's RackEntraIdAuth's middleware's job).
  def saml_login_response (sessionindex)
    Base64.strict_encode64(<<~XML)
      <samlp:Response xmlns:samlp="urn:oasis:names:tc:SAML:2.0:protocol" xmlns:saml="urn:oasis:names:tc:SAML:2.0:assertion" ID="_response" Version="2.0" IssueInstant="2026-01-01T00:00:00Z">
        <samlp:Status><samlp:StatusCode Value="urn:oasis:names:tc:SAML:2.0:status:Success"/></samlp:Status>
        <saml:Assertion ID="_assertion" Version="2.0" IssueInstant="2026-01-01T00:00:00Z">
          <saml:Issuer>https://idp.example.com/</saml:Issuer>
          <ds:Signature xmlns:ds="http://www.w3.org/2000/09/xmldsig#">
            <ds:SignedInfo>
              <ds:CanonicalizationMethod Algorithm="http://www.w3.org/2001/10/xml-exc-c14n#"/>
              <ds:SignatureMethod Algorithm="http://www.w3.org/2001/04/xmldsig-more#rsa-sha256"/>
              <ds:Reference URI="#_assertion">
                <ds:Transforms>
                  <ds:Transform Algorithm="http://www.w3.org/2000/09/xmldsig#enveloped-signature"/>
                  <ds:Transform Algorithm="http://www.w3.org/2001/10/xml-exc-c14n#"/>
                </ds:Transforms>
                <ds:DigestMethod Algorithm="http://www.w3.org/2001/04/xmlenc#sha256"/>
                <ds:DigestValue>AAAA</ds:DigestValue>
              </ds:Reference>
            </ds:SignedInfo>
            <ds:SignatureValue>AAAA</ds:SignatureValue>
          </ds:Signature>
          <saml:Subject><saml:NameID>rtables@example.com</saml:NameID></saml:Subject>
          <saml:AuthnStatement AuthnInstant="2026-01-01T00:00:00Z" SessionIndex="#{sessionindex}"/>
        </saml:Assertion>
      </samlp:Response>
    XML
  end

  # A deflated, base64-encoded SAML logout request (HTTP-Redirect binding)
  # naming the given sessionindexes.
  def saml_logout_request (*sessionindexes)
    session_index_elements = sessionindexes.map { |index| "<samlp:SessionIndex>#{index}</samlp:SessionIndex>" }.join

    xml = <<~XML
      <samlp:LogoutRequest xmlns:samlp="urn:oasis:names:tc:SAML:2.0:protocol" xmlns:saml="urn:oasis:names:tc:SAML:2.0:assertion" ID="_logout" Version="2.0" IssueInstant="2026-01-01T00:00:00Z">
        <saml:Issuer>https://idp.example.com/</saml:Issuer>
        <saml:NameID>rtables@example.com</saml:NameID>
        #{session_index_elements}
      </samlp:LogoutRequest>
    XML

    Base64.strict_encode64(Zlib::Deflate.deflate(xml, Zlib::BEST_COMPRESSION)[2..-5])
  end

  # Logs in as a new browser, returning that browser's cookies.
  def log_in (sessionindex)
    clear_cookies
    request(app { |session, _request| session[:entra_id] = { 'name' => sessionindex } },
            ACS_URL, method: 'POST', params: { 'SAMLResponse' => saml_login_response(sessionindex) })
    @cookies.dup
  end
end

class Minitest::Test
  include SessionStoreTestHelpers
end
