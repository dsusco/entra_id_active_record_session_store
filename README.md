# EntraIdActiveRecordSessionStore

An [Active Record session store](https://github.com/rails/activerecord-session_store) for apps that use [RackEntraIdAuth](https://github.com/dsusco/rack_entra_id_auth) for Microsoft Entra ID (SAML) authentication.

It works like the regular `:active_record_store`, but it also records the SAML `SessionIndex` of each Entra ID login. When Entra ID sends an IdP-initiated single logout request, every session with a sessionindex named in that request is destroyed, not just the session in the browser the request arrived in. This is what makes single logout actually log users out of your app.

## Requirements

- Ruby 3.2+
- Rails 7.2+ (Active Record 7.2+)
- RackEntraIdAuth 1.4+

## Installation

Add the gem to your Gemfile:

```ruby
gem 'entra_id_active_record_session_store'
```

Then run `bundle install`. This also installs RackEntraIdAuth and activerecord-session_store. If you haven't set up RackEntraIdAuth yet, follow its README first.

## Setup

Generate the sessions table migration, which adds a `sessionindex` column to the usual session store table, and run it:

```bash
bin/rails generate entra_id_active_record_session_store:migration
bin/rails db:migrate
```

Then generate the initializer that switches your app to this session store:

```bash
bin/rails generate entra_id_active_record_session_store:initializer
```

This creates `config/initializers/session_store.rb`:

```ruby
Rails.application.config.session_store :entra_id_active_record_store, key: '_your_app_session'
```

Finally, turn on single logout in RackEntraIdAuth. It's off by default, and without it the IdP's logout requests are ignored:

```ruby
# config/initializers/rack_entra_id_auth.rb
config.skip_single_logout = false
```

## How it works

When a request carries a login response from Entra ID (a POST of `SAMLResponse` to your assertion consumer service URL), the store saves the response's sessionindex on the session record. RackEntraIdAuth's middleware has already validated the response by then; the store only reads it.

When a request carries a logout request from Entra ID (a `SAMLRequest` at your single logout service URL), the store destroys every session whose sessionindex the logout request names. It then destroys the current session, as `:active_record_store` normally would.

Everything else, such as loading and saving sessions, session ID handling and the `db:sessions:trim` task, comes from activerecord-session_store unchanged.

## Upgrading an existing sessions table

If you already use `:active_record_store`, add the column and index instead of creating a new table:

```ruby
add_column :sessions, :sessionindex, :string
add_index  :sessions, :sessionindex, unique: true
```

## Development

The tests use an in-memory SQLite database:

```bash
bundle install
bundle exec rake test
bundle exec rubocop
```

## License

Available as open source under the terms of the [MIT License](MIT-LICENSE).
