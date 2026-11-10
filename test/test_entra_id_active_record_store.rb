require 'test_helper'

class TestEntraIdActiveRecordStore < Minitest::Test
  def test_stores_sessions_like_active_record_store
    request(app { |session, _request| session[:counter] = 1 }, 'https://app.example.com/')

    assert_equal 1, session_class.count
    assert_equal({ 'counter' => 1 }, session_class.last.data)
    assert_nil session_class.last.sessionindex
  end

  def test_reads_sessions_back
    request(app { |session, _request| session[:counter] = 1 }, 'https://app.example.com/')

    seen = nil
    request(app { |session, _request| seen = session[:counter] }, 'https://app.example.com/')

    assert_equal 1, seen
  end

  def test_login_response_stores_sessionindex
    log_in('_index-1')

    assert_equal 1, session_class.count
    assert_equal '_index-1', session_class.last.sessionindex
    assert_equal({ 'entra_id' => { 'name' => '_index-1' } }, session_class.last.data)
  end

  def test_login_response_tags_an_existing_session
    request(app { |session, _request| session[:before_login] = true }, 'https://app.example.com/')

    request(app { |session, _request| session[:entra_id] = {} },
            SessionStoreTestHelpers::ACS_URL, method: 'POST',
                                              params: { 'SAMLResponse' => saml_login_response('_index-1') })

    assert_equal 1, session_class.count
    assert_equal '_index-1', session_class.last.sessionindex
  end

  def test_sessionindex_survives_later_requests
    log_in('_index-1')

    request(app { |session, _request| session[:counter] = 2 }, 'https://app.example.com/')

    assert_equal '_index-1', session_class.last.sessionindex
    assert_equal 2, session_class.last.data['counter']
  end

  def test_posts_elsewhere_do_not_set_sessionindex
    request(app { |session, _request| session[:counter] = 1 },
            'https://app.example.com/other', method: 'POST',
                                             params: { 'SAMLResponse' => saml_login_response('_index-1') })

    assert_nil session_class.last.sessionindex
  end

  # sessionindexes of the sessions left in the table. Destroying a session
  # leaves a fresh, empty one for the browser (ActiveRecordStore behavior), so
  # sessions without a sessionindex are ignored.
  def remaining_sessionindexes
    session_class.where.not(sessionindex: nil).order(:sessionindex).pluck(:sessionindex)
  end

  def logout_request_url (*sessionindexes)
    "#{SessionStoreTestHelpers::SLO_SERVICE_URL}?SAMLRequest=" +
      URI.encode_www_form_component(saml_logout_request(*sessionindexes))
  end

  def test_idp_logout_request_destroys_sessions_with_matching_sessionindex
    first_browser = log_in('_index-1')
    log_in('_index-2')
    log_in('_index-3')

    # the IdP's logout request arrives in the first browser
    @cookies = first_browser
    request(app { |session, _request| session.destroy }, logout_request_url('_index-1', '_index-2'))

    assert_equal ['_index-3'], remaining_sessionindexes
  end

  def test_idp_logout_request_from_a_browser_without_a_session
    log_in('_index-1')
    log_in('_index-2')

    clear_cookies
    request(app { |session, _request| session.destroy }, logout_request_url('_index-1'))

    assert_equal ['_index-2'], remaining_sessionindexes
  end

  def test_idp_logout_request_without_session_indexes_only_destroys_the_current_session
    log_in('_index-1')
    log_in('_index-2')

    request(app { |session, _request| session.destroy }, logout_request_url)

    assert_equal ['_index-1'], remaining_sessionindexes
  end

  def test_regular_logout_destroys_only_the_current_session
    log_in('_index-1')
    log_in('_index-2')

    request(app { |session, _request| session.destroy }, 'https://app.example.com/logout')

    assert_equal ['_index-1'], remaining_sessionindexes
  end

  def test_logout_request_at_another_path_is_a_regular_logout
    log_in('_index-1')
    log_in('_index-2')

    request(app { |session, _request| session.destroy },
            "https://app.example.com/logout?SAMLRequest=#{URI.encode_www_form_component(saml_logout_request('_index-1'))}")

    assert_equal ['_index-1'], remaining_sessionindexes
  end

  def test_logout_then_new_session_starts_empty
    log_in('_index-1')

    request(app { |session, _request| session.destroy }, 'https://app.example.com/logout')

    seen = :unset
    request(app { |session, _request| seen = session[:entra_id] }, 'https://app.example.com/')

    assert_nil seen
  end
end
