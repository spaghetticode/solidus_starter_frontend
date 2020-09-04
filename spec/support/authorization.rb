# frozen_string_literal: true

module Authorization
  def stub_spree_current_user(spree_api_key: 'fake')
    Spree::StoreController.define_method(:spree_current_user) do
      Spree.user_class.find_by(spree_api_key: spree_api_key)
    end

    before do
      allow(Spree.user_class).to receive(:find_by)
        .with(hash_including(:spree_api_key))
        .and_return(user)
    end
  end
end
