require "test_helper"

class PublicDemosControllerTest < ActionDispatch::IntegrationTest
  def with_public_demo_only_routes
    with_env_overrides(
      "PUBLIC_DEMO_ONLY" => "true",
      "PUBLIC_DEMO_SLUG" => "test-tahiti",
      "PUBLIC_DEMO_EMAIL" => users(:family_admin).email,
    ) do
      yield
    end
  end

  test "shows configured public demo without authentication" do
    with_env_overrides("PUBLIC_DEMO_SLUG" => "test-tahiti", "PUBLIC_DEMO_EMAIL" => users(:family_admin).email) do
      get public_demo_path("test-tahiti")

      assert_response :success
      assert_select "html[lang='en']"
      assert_match "Public Demo", response.body
      assert_match users(:family_admin).email, response.body
      assert_match families(:dylan_family).name, response.body
    end
  end

  test "renders the public demo in french when locale is fr" do
    with_env_overrides("PUBLIC_DEMO_SLUG" => "test-tahiti", "PUBLIC_DEMO_EMAIL" => users(:family_admin).email) do
      get public_demo_path("test-tahiti"), params: {
        locale: "fr",
        period: "last_30_days",
        cashflow_period: "last_90_days"
      }

      assert_response :success
      assert_select "html[lang='fr']"
      assert_match "Démo publique", response.body
      assert_match "Langue", response.body
      assert_match "Flux de trésorerie", response.body
      assert_select "a[href*='locale=en'][href*='period=last_30_days'][href*='cashflow_period=last_90_days']", text: "EN"
      assert_select "a[href*='locale=fr'][href*='period=last_30_days'][href*='cashflow_period=last_90_days']", text: "FR"
      assert_select "input[type='hidden'][name='locale'][value='fr']", count: 2
      assert_select "input[type='hidden'][name='cashflow_period'][value='last_90_days']", count: 1
      assert_select "input[type='hidden'][name='period'][value='last_30_days']", count: 1
    end
  end

  test "shows the public demo budget without authentication" do
    with_env_overrides("PUBLIC_DEMO_SLUG" => "test-tahiti", "PUBLIC_DEMO_EMAIL" => users(:family_admin).email) do
      get public_demo_budget_path("test-tahiti")

      assert_response :success
      assert_select "html[lang='en']"
      assert_match "Budget", response.body
      assert_match "Read-only", response.body
    end
  end

  test "public demo only mode redirects demo entry to the full app" do
    with_public_demo_only_routes do
      get public_demo_path("test-tahiti")

      assert_redirected_to root_path
    end
  end

  test "public demo only mode redirects transaction entry to the full transactions page" do
    with_public_demo_only_routes do
      get public_demo_transactions_path("test-tahiti"), params: {
        locale: "fr",
        per_page: 30,
        q: { search: "Starbucks" },
      }

      assert_redirected_to transactions_path(locale: "fr", per_page: "30", q: { search: "Starbucks" })
    end
  end

  test "public demo only mode redirects budget entry to the full budget page" do
    with_public_demo_only_routes do
      budget = Budget.find_or_bootstrap(users(:family_admin).family, start_date: Date.current)

      get public_demo_budget_path("test-tahiti"), params: { locale: "fr" }

      assert_redirected_to budget_path(budget, locale: "fr")
    end
  end

  test "falls back to english when locale is invalid" do
    with_env_overrides("PUBLIC_DEMO_SLUG" => "test-tahiti", "PUBLIC_DEMO_EMAIL" => users(:family_admin).email) do
      get public_demo_path("test-tahiti"), params: { locale: "de" }

      assert_response :success
      assert_select "html[lang='en']"
      assert_match "Public Demo", response.body
      assert_match "Language", response.body
    end
  end

  test "returns not found for unknown slug" do
    with_env_overrides("PUBLIC_DEMO_SLUG" => "test-tahiti", "PUBLIC_DEMO_EMAIL" => users(:family_admin).email) do
      get public_demo_path("autre-slug")

      assert_response :not_found
    end
  end

  test "public demo only mode shows the full app without authentication" do
    with_public_demo_only_routes do
      get root_path

      assert_response :success
      assert_select "html[lang='en']"
      assert_match "Transactions", response.body
      assert_match "Budgets", response.body
      assert_match "Public demo mode.", response.body
    end
  end

  test "public demo only mode allows private get routes" do
    with_public_demo_only_routes do
      get transactions_path

      assert_response :success
      assert_match "Transactions", response.body
    end
  end

  test "public demo only mode blocks write requests" do
    with_public_demo_only_routes do
      post transactions_path

      assert_redirected_to root_path
    end
  end
end
