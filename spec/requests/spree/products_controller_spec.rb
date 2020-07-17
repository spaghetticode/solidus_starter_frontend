# frozen_string_literal: true

require 'spec_helper'

describe Spree::ProductsController, type: :request do
  let!(:product) { create(:product, available_on: 1.year.from_now) }
  let(:user) { mock_model(Spree.user_class) }
  let(:searcher_class) { instance_double(Spree::Config.searcher_class) }

  stub_spree_current_user

  before do
    allow(Spree::Config.searcher_class).to receive(:new) { searcher_class }
    allow(searcher_class).to receive(:current_user=)
    allow(searcher_class).to receive(:pricing_options=)
    allow(searcher_class).to receive(:retrieve_products) { [product] }
  end

  context 'as an admin' do
    let(:user) { mock_model(Spree.user_class, has_spree_role?: 'admin', spree_api_key: 'fake') }

    # Regression test for https://github.com/spree/spree/issues/1390
    it "allows admins to view non-active products" do
      get spree.product_path(product.to_param)
      expect(response.status).to eq(200)
    end

    # Regression test for https://github.com/spree/spree/issues/2249
    it "doesn't error when given an invalid referer" do
      # Previously a URI::InvalidURIError exception was being thrown
      get spree.product_path(product.to_param), headers: { 'HTTP_REFERER' => 'not|a$url' }
    end
  end

  it "cannot view non-active products" do
    expect do
      get spree.product_path(product.to_param)
    end.to raise_error(ActiveRecord::RecordNotFound)
  end

  it "should provide the current user to the searcher class" do
    get spree.products_path

    expect(searcher_class).to have_received(:current_user=).with(user)
    expect(response.status).to eq(200)
  end
end
