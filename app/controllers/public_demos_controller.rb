class PublicDemosController < ApplicationController
  DEFAULT_LOCALE = "en".freeze
  SUPPORTED_LOCALES = %w[en fr].freeze

  layout "public_demo"

  skip_authentication
  skip_around_action :switch_locale
  skip_before_action :require_onboarding_and_upgrade
  skip_before_action :restore_active_tabs
  skip_before_action :set_default_chat

  helper_method :demo_path_for, :public_demo_clear_filter_path

  before_action :set_demo_tab
  around_action :switch_demo_locale
  before_action :set_demo_locale
  before_action :set_demo_config
  before_action :set_period
  before_action :set_cashflow_period
  before_action :set_demo_user
  before_action :set_demo_data
  before_action :set_budget_data, only: :budget
  before_action :set_transactions_data, only: :transactions

  def show
    return redirect_to root_path(request.query_parameters), status: :see_other if PublicDemoConfig.enabled?
  end

  def transactions
    return redirect_to transactions_path(request.query_parameters), status: :see_other if PublicDemoConfig.enabled?
  end

  def budget
    return redirect_to budget_path(@budget, locale: @demo_locale), status: :see_other if PublicDemoConfig.enabled?
  end

  private
    def set_demo_tab
      @demo_tab = case action_name
      when "transactions"
        :transactions
      when "budget"
        :budget
      else
        :overview
      end
    end

    def set_demo_locale
      @demo_locale = selected_demo_locale
      @demo_page_params = request.query_parameters.except("locale")
    end

    def set_demo_config
      @demo_slug = PublicDemoConfig.slug
      @demo_email = PublicDemoConfig.email
      @demo_title = @demo_slug.to_s.tr("-", " ").titleize

      raise ActiveRecord::RecordNotFound unless params[:slug] == @demo_slug
    end

    def set_demo_user
      @demo_user = User.find_by!(email: @demo_email)
      @demo_family = @demo_user.family
    end

    def set_demo_data
      @balance_sheet = @demo_family.balance_sheet
      @accounts = @demo_family.accounts.visible.with_attached_logo

      income_totals = @demo_family.income_statement.income_totals(period: @cashflow_period)
      expense_totals = @demo_family.income_statement.expense_totals(period: @cashflow_period)

      @cashflow_sankey_data = build_cashflow_sankey_data(
        income_totals,
        expense_totals,
        @demo_family.currency
      )
    end

    def set_transactions_data
      @q = transaction_search_params
      @search = Transaction::Search.new(@demo_family, filters: @q)

      base_scope = @search.transactions_scope
                          .reverse_chronological
                          .includes(
                            { entry: :account },
                            :category, :merchant, :tags,
                            :transfer_as_inflow, :transfer_as_outflow
                          )

      @pagy, @transactions = pagy(base_scope, limit: transaction_per_page)
      @demo_accounts = @demo_family.accounts.visible.alphabetically
      @demo_categories = [ Category.uncategorized ].concat(@demo_family.categories.alphabetically.to_a)
      @demo_merchants = @demo_family.assigned_merchants.alphabetically
      @demo_tags = @demo_family.tags.alphabetically
    end

    def set_budget_data
      requested_budget_date = params[:month_year].presence && Budget.param_to_date(params[:month_year])
      @budget = Budget.find_or_bootstrap(@demo_family, start_date: requested_budget_date || Date.current)
      raise ActiveRecord::RecordNotFound unless @budget

      @budget_name = I18n.l(@budget.start_date, format: "%B %Y")
    rescue Date::Error
      @budget = Budget.find_or_bootstrap(@demo_family, start_date: Date.current)
      raise ActiveRecord::RecordNotFound unless @budget

      @budget_name = I18n.l(@budget.start_date, format: "%B %Y")
    end

    def set_period
      @period = Period.from_key(params[:period] || "last_30_days")
    rescue Period::InvalidKeyError
      @period = Period.last_30_days
    end

    def set_cashflow_period
      @cashflow_period = Period.from_key(params[:cashflow_period] || "last_30_days")
    rescue Period::InvalidKeyError
      @cashflow_period = Period.last_30_days
    end

    def build_cashflow_sankey_data(income_totals, expense_totals, currency_symbol)
      nodes = []
      links = []
      node_indices = {}

      add_node = ->(unique_key, display_name, value, percentage, color) {
        node_indices[unique_key] ||= begin
          nodes << { name: display_name, value: value.to_f.round(2), percentage: percentage.to_f.round(1), color: color }
          nodes.size - 1
        end
      }

      total_income_val = income_totals.total.to_f.round(2)
      total_expense_val = expense_totals.total.to_f.round(2)

      cash_flow_idx = add_node.call(
        "cash_flow_node",
        I18n.t("public_demos.show.cash_flow", locale: @demo_locale),
        total_income_val,
        0,
        "var(--color-success)"
      )

      income_totals.category_totals.each do |category_total|
        next if category_total.category.parent_id.present?

        value = category_total.total.to_f.round(2)
        next if value.zero?

        percentage_of_total_income = total_income_val.zero? ? 0 : (value / total_income_val * 100).round(1)
        node_color = category_total.category.color.presence || Category::COLORS.sample

        current_cat_idx = add_node.call(
          "income_#{category_total.category.id}",
          category_total.category.name,
          value,
          percentage_of_total_income,
          node_color
        )

        links << {
          source: current_cat_idx,
          target: cash_flow_idx,
          value: value,
          color: node_color,
          percentage: percentage_of_total_income
        }
      end

      expense_totals.category_totals.each do |category_total|
        next if category_total.category.parent_id.present?

        value = category_total.total.to_f.round(2)
        next if value.zero?

        percentage_of_total_expense = total_expense_val.zero? ? 0 : (value / total_expense_val * 100).round(1)
        node_color = category_total.category.color.presence || Category::UNCATEGORIZED_COLOR

        current_cat_idx = add_node.call(
          "expense_#{category_total.category.id}",
          category_total.category.name,
          value,
          percentage_of_total_expense,
          node_color
        )

        links << {
          source: cash_flow_idx,
          target: current_cat_idx,
          value: value,
          color: node_color,
          percentage: percentage_of_total_expense
        }
      end

      leftover = (total_income_val - total_expense_val).round(2)
      if leftover.positive?
        percentage_of_total_income_for_surplus = total_income_val.zero? ? 0 : (leftover / total_income_val * 100).round(1)
        surplus_idx = add_node.call(
          "surplus_node",
          I18n.t("public_demos.show.surplus", locale: @demo_locale),
          leftover,
          percentage_of_total_income_for_surplus,
          "var(--color-success)"
        )
        links << {
          source: cash_flow_idx,
          target: surplus_idx,
          value: leftover,
          color: "var(--color-success)",
          percentage: percentage_of_total_income_for_surplus
        }
      end

      if node_indices["cash_flow_node"]
        nodes[node_indices["cash_flow_node"]][:percentage] = 100.0
      end

      { nodes: nodes, links: links, currency_symbol: Money::Currency.new(currency_symbol).symbol }
    end

    def switch_demo_locale(&action)
      I18n.with_locale(selected_demo_locale, &action)
    end

    def selected_demo_locale
      requested_locale = params[:locale].to_s

      if SUPPORTED_LOCALES.include?(requested_locale)
        requested_locale
      else
        DEFAULT_LOCALE
      end
    end

    def transaction_search_params
      cleaned_params = params.fetch(:q, ActionController::Parameters.new)
                           .permit(
                             :start_date, :end_date, :search, :amount,
                             :amount_operator, :active_accounts_only,
                             accounts: [], account_ids: [],
                             categories: [], merchants: [], types: [], tags: []
                           )
                           .to_h
                           .with_indifferent_access
                           .compact_blank

      cleaned_params.delete(:amount_operator) unless cleaned_params[:amount].present?
      cleaned_params
    end

    def transaction_per_page
      per_page = params[:per_page].to_i
      [ 10, 20, 30, 50 ].include?(per_page) ? per_page : 20
    end

    def demo_path_for(tab, route_params = {})
      case tab.to_sym
      when :transactions
        public_demo_transactions_path(@demo_slug, route_params)
      when :budget
        public_demo_budget_path(@demo_slug, route_params)
      else
        public_demo_path(@demo_slug, route_params)
      end
    end

    def public_demo_clear_filter_path(param_key, param_value = nil)
      route_params = request.query_parameters.deep_dup
      query_params = route_params["q"].is_a?(Hash) ? route_params["q"].deep_dup : {}

      if query_params[param_key].is_a?(Array)
        query_params[param_key] = query_params[param_key] - [ param_value ]
        query_params.delete(param_key) if query_params[param_key].blank?
      else
        query_params.delete(param_key)
      end

      query_params.delete("amount_operator") unless query_params["amount"].present?
      route_params["q"] = query_params.presence
      route_params.except!("page")

      public_demo_transactions_path(@demo_slug, route_params)
    end
end
