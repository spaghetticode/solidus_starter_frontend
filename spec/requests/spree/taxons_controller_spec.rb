# frozen_string_literal: true

require 'spec_helper'

describe Spree::TaxonsController, type: :request do
  let(:user) { mock_model(Spree.user_class, has_spree_role?: 'admin', spree_api_key: 'fake') }
  let(:searcher_class) { instance_double(Spree::Config.searcher_class) }

  stub_spree_current_user

  before do
    allow(Spree::Config.searcher_class).to receive(:new) { searcher_class }
    allow(searcher_class).to receive(:current_user=)
    allow(searcher_class).to receive(:pricing_options=)
    allow(searcher_class).to receive(:retrieve_products) { [] }
  end

  it "provides the current user to the searcher class" do
    taxon = create(:taxon, permalink: "test")
    get spree.nested_taxons_path(taxon.permalink)

    expect(searcher_class).to have_received(:current_user=).with(user)
    expect(response.status).to eq(200)
  end
end
