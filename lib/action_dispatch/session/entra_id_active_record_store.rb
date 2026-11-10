require 'active_record/session_store'
require 'action_dispatch/session/active_record_store'
require 'rack_entra_id_auth/entra_id_request'

module ActionDispatch
  module Session
    # An Active Record session store that records the SAML sessionindex of each
    # Entra ID login, so IdP-initiated single logout requests can destroy every
    # session belonging to that login.
    #
    # Everything else is inherited from ActiveRecordStore, so upstream fixes
    # and optimizations still apply.
    class EntraIdActiveRecordStore < ActionDispatch::Session::ActiveRecordStore
      SESSIONINDEX_KEY = 'entra_id_active_record_store.sessionindex'.freeze

      private

        # Tags the session record with the sessionindex from a login response.
        # Called when the session is loaded and again when it's written, so the
        # sessionindex is saved along with the session data.
        def get_session_model (request, id)
          model, id = super

          sessionindex = login_response_sessionindex(request)
          model.sessionindex = sessionindex if sessionindex.present?

          [model, id]
        end

        # Destroys every session with a sessionindex named in an IdP-initiated
        # single logout request, then lets ActiveRecordStore handle the
        # current session (including :drop and :renew).
        def delete_session (request, session_id, options)
          entra_id_request = RackEntraIdAuth::EntraIdRequest.new(request)

          if entra_id_request.logout_request?
            session_indexes = entra_id_request.saml_logout_request.session_indexes

            logger.silence do
              session_class.where(sessionindex: session_indexes).destroy_all if session_indexes.present?
            end
          end

          super
        end

        # The sessionindex from the login response in this request, if there
        # is one. Memoized in the request env so the SAML response is only
        # parsed once.
        #
        # This builds the ruby-saml response directly rather than using
        # EntraIdRequest#saml_auth_response, which reads and writes the
        # session, because this runs while the session itself is loading. The
        # middleware has already validated the response; this only reads it.
        def login_response_sessionindex (request)
          return request.get_header(SESSIONINDEX_KEY) if request.has_header?(SESSIONINDEX_KEY)

          request.set_header(SESSIONINDEX_KEY, parse_login_response_sessionindex(request))
        end

        def parse_login_response_sessionindex (request)
          return unless RackEntraIdAuth::EntraIdRequest.new(request).login_response?

          settings = OneLogin::RubySaml::Settings.new(RackEntraIdAuth.config.ruby_saml_settings)

          OneLogin::RubySaml::Response.new(request.POST['SAMLResponse'], settings: settings).sessionindex
        end
    end
  end
end
