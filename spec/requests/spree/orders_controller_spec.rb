# frozen_string_literal: true

require 'spec_helper'

describe Spree::OrdersController, type: :request do
  let!(:store) { create(:store) }
  let(:user) { create(:user) }
  let(:variant) { create(:variant) }

  stub_spree_current_user

  context "#populate" do
    it "creates a new order when none specified" do
      expect do
        post spree.populate_orders_path, params: { variant_id: variant.id }
      end.to change(Spree::Order, :count).by(1)

      expect(response).to be_redirect
      expect(response.cookies['guest_token']).not_to be_blank

      jar = ActionDispatch::Cookies::CookieJar.build(request, cookies.to_hash)
      order_by_token = Spree::Order.find_by(guest_token: jar.signed[:guest_token])

      expect(order_by_token).to be_persisted
    end

    context "when variant" do
      it "handles population" do
        expect do
          post spree.populate_orders_path, params: { variant_id: variant.id, quantity: 5 }
        end.to change { user.orders.count }.by(1)
        order = user.orders.last
        expect(response).to redirect_to spree.cart_path
        expect(order.line_items.size).to eq(1)
        line_item = order.line_items.first
        expect(line_item.variant_id).to eq(variant.id)
        expect(line_item.quantity).to eq(5)
      end

      context 'when fails to populate' do
        it "shows an error when quantity is invalid" do
          post(
            spree.populate_orders_path,
            headers: { 'HTTP_REFERER' => spree.root_path },
            params: { variant_id: variant.id, quantity: -1 }
          )

          expect(response).to redirect_to(spree.root_path)
          expect(flash[:error]).to eq(
            I18n.t('spree.please_enter_reasonable_quantity')
          )
        end
      end

      context "when quantity is empty string" do
        it "populates order with 1 of given variant" do
          expect do
            post spree.populate_orders_path, params: { variant_id: variant.id, quantity: '' }
          end.to change { Spree::Order.count }.by(1)
          order = Spree::Order.last
          expect(response).to redirect_to spree.cart_path
          expect(order.line_items.size).to eq(1)
          line_item = order.line_items.first
          expect(line_item.variant_id).to eq(variant.id)
          expect(line_item.quantity).to eq(1)
        end
      end

      context "when quantity is nil" do
        it "should populate order with 1 of given variant" do
          expect do
            post spree.populate_orders_path, params: { variant_id: variant.id, quantity: nil }
          end.to change { Spree::Order.count }.by(1)
          order = Spree::Order.last
          expect(response).to redirect_to spree.cart_path
          expect(order.line_items.size).to eq(1)
          line_item = order.line_items.first
          expect(line_item.variant_id).to eq(variant.id)
          expect(line_item.quantity).to eq(1)
        end
      end
    end
  end

  context '#edit' do
    let!(:order) { create(:order, user_id: user.id, store: store) }

    it 'renders the cart' do
      get spree.edit_order_path(order.number)

      expect(flash[:error]).to be_nil
      expect(response).to be_ok
    end

    context 'with another order number than the current_order' do
      let(:other_order) { create(:completed_order_with_totals) }

      it 'displays error message' do
        get spree.edit_order_path(other_order.number)

        expect(flash[:error]).to eq "You may only edit your current shopping cart."
        expect(response).to redirect_to spree.cart_path
      end
    end
  end

  context "#update" do
    let!(:order) { create(:order_with_line_items, user_id: user.id, store: store) }

    context "with authorization" do
      before do
        ApplicationController.allow_forgery_protection = false
      end

      it "renders the edit view (on failure)" do
        # email validation is only after address state
        order.update_column(:state, "delivery")
        put spree.order_path(order.number), params: { order: { email: "" } }
        expect(response).to render_template :edit
      end

      it "redirects to cart path (on success)" do
        put spree.order_path(order.number), params: { order: { email: 'test@email.com' } }
        expect(response).to redirect_to(spree.cart_path)
      end

      it "advances the order if :checkout button is pressed" do
        expect do
          put spree.order_path(order.number), params: { checkout: true }
        end.to change { order.reload.state }.from('cart').to('address')

        expect(response).to redirect_to spree.checkout_state_path('address')
      end
    end
  end

  context "#empty" do
    let!(:order) { create(:order_with_line_items, user_id: user.id, store: store) }

    before { ActionController::Base.allow_forgery_protection = false }

    it "it destroys line items in the current order" do
      put spree.empty_cart_path

      expect(response).to redirect_to(spree.cart_path)
      expect(order.reload.line_items).to be_blank
    end
  end

  context "when line items quantity is 0" do
    let!(:order) { create(:order, user_id: user.id, store: store) }
    let!(:line_item) { order.contents.add(variant, 1) }
    let(:variant) { create(:variant) }

    before { ActionController::Base.allow_forgery_protection = false }

    it "removes line items on update" do
      expect(order.line_items.count).to eq 1

      put spree.order_path(order.number), params: { order: { line_items_attributes: { "0" => { id: line_item.id, quantity: 0 } } } }

      expect(order.reload.line_items.count).to eq 0
    end
  end

  describe '#edit' do
    it "builds a new valid order with complete meta-data" do
      get spree.cart_path

      order = controller.instance_variable_get(:@order)

      aggregate_failures do
        expect(order).to be_valid
        expect(order).not_to be_persisted
        expect(order.store).to be_present
        expect(order.user).to eq(user)
        expect(order.created_by).to eq(user)
      end
    end
  end
end
