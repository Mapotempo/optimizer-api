I18n.load_path += Dir['./config/locales/*.yml']
I18n.load_path += Dir['lib/grape/locale/*.yml']
I18n::Backend::Simple.include(I18n::Backend::Fallbacks)
I18n.enforce_available_locales = false
I18n.available_locales = [:en, :fr, :es, :legacy]
I18n.default_locale = :en
