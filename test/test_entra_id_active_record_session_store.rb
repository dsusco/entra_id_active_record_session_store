require 'test_helper'

class TestEntraIdActiveRecordSessionStore < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::EntraIdActiveRecordSessionStore::VERSION
  end

  def test_is_an_active_record_store
    assert_operator ActionDispatch::Session::EntraIdActiveRecordStore, :<, ActionDispatch::Session::ActiveRecordStore
  end

  def test_rails_can_find_the_store_by_name
    # config.session_store :entra_id_active_record_store looks the class up like this
    assert_equal ActionDispatch::Session::EntraIdActiveRecordStore,
                 ActionDispatch::Session.const_get(:entra_id_active_record_store.to_s.camelize)
  end
end
