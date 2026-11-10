require 'test_helper'

class TestMigrationTemplate < Minitest::Test
  def columns
    ActiveRecord::Base.connection.columns(:sessions).to_h { |column| [column.name, column] }
  end

  def indexes
    ActiveRecord::Base.connection.indexes(:sessions).to_h { |index| [index.columns, index] }
  end

  def test_renders_a_versioned_migration
    assert_match(/class CreateSessions < ActiveRecord::Migration\[\d+\.\d+\]/,
                 SessionStoreTestHelpers::MigrationTemplate.new.render)
  end

  def test_creates_session_columns
    assert_equal %w[created_at data id session_id sessionindex updated_at], columns.keys.sort
    refute columns['session_id'].null
    assert columns['sessionindex'].null
  end

  def test_creates_indexes
    assert indexes[['session_id']].unique
    assert indexes[['sessionindex']]
    assert indexes[['updated_at']]
  end
end
