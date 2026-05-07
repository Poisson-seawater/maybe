module PublicDemoConfig
  module_function

  def enabled?
    ActiveModel::Type::Boolean.new.cast(ENV["PUBLIC_DEMO_ONLY"])
  end

  def slug
    ENV.fetch("PUBLIC_DEMO_SLUG", "test-tahiti")
  end

  def email
    ENV.fetch("PUBLIC_DEMO_EMAIL", "tahiti@gmail.com")
  end
end
