# frozen_string_literal: true
require 'byebug'
require 'spec_helper'

describe Spree::CheckoutController, type: :request do
  let(:user) { create(:user) }

  let(:address_params) do
    address = build(:address)
    address.attributes.except("created_at", "updated_at")
  end

  stub_spree_current_user

  context "#edit" do
    let!(:order) { create(:order_with_line_items, user_id: user.id) }

    it 'checks if the user is authorized for :edit' do
      get spree.checkout_path, params: { state: "address" }

      expect(status).to eq(200)
    end

    it "redirects to the cart path if checkout_allowed? return false" do
      order.line_items.destroy_all
      get spree.checkout_path, params: { state: "delivery" }

      expect(response).to redirect_to(spree.cart_path)
    end

    it "redirects to the cart path if current_order is nil" do
      order.destroy 
      get spree.checkout_path, params: { state: "delivery" }

      expect(response).to redirect_to(spree.cart_path)
    end

    it "redirects to cart if order is completed" do
      order.touch(:completed_at)
      get spree.checkout_path, params: { state: "address" }
      
      expect(response).to redirect_to(spree.cart_path)
    end

    # Regression test for https://github.com/spree/spree/issues/2280
    it "redirects to current step trying to access a future step" do
      order.update_column(:state, "address")
  
      get spree.checkout_path, params: { state: "delivery" }
      expect(response).to redirect_to spree.checkout_state_path("address")
    end

    context "when entering the checkout" do
      before do
        # The first step for checkout controller is address
        # Transitioning into this state first is required
        order.update(state: "address", user_id: nil)
      end

      it "associates the order with a user" do
        pending('cannot set signed cookies in request spec so only order with ')
        expect do
          get spree.checkout_path
        end.to change(order, :user_id).from(nil).to(user.id)
      end
    end
  end

  context "#update" do
    let!(:order) { create(:order_with_line_items, user_id: user.id) }

    before { ApplicationController.allow_forgery_protection = false }

    it 'checks if the user is authorized for :edit' do
      expect do
        patch spree.update_checkout_path(state: 'address')
      end.to change { order.reload.state }.from('cart').to('delivery')
    end

    context "save successful" do
      def post_address
        patch spree.update_checkout_path(state: "address",
          order: {
            bill_address_attributes: address_params,
            use_billing: true
          }
        )
      end

      let!(:payment_method) { create(:payment_method) }

      context "with the order in the cart state", partial_double_verification: false do
        before do
          order.update_column(:state, "cart")
        end

        it "assigns order" do
          patch spree.update_checkout_path(state: 'address')
          expect(assigns[:order]).not_to be_nil
        end

        it "advances the state" do
          post_address
          expect(order.reload.state).to eq("delivery")
        end

        it "should redirect the next state" do
          post_address
          expect(response).to redirect_to spree.checkout_state_path("delivery")
        end

        context "current_user respond to save address method" do
          def post_persist_address
            patch spree.update_checkout_path(state: "address",
              order: {
                bill_address_attributes: address_params,
                use_billing: true
              },
              save_user_address: "1"
            )
          end
  
          it "calls persist order address on user" do
            user.user_addresses.destroy

            expect { post_persist_address }.to change { user.user_addresses.count }.from(0).to(1) 
          end
        end

        context "current_user doesnt respond to persist_order_address" do
          it "doesnt raise any error" do
            pending('should the request spec be aware of this?')
            post :update, params: {
              state: "address",
              order: {
                bill_address_attributes: address_params,
                use_billing: true
              },
              save_user_address: "1"
            }
          end
        end
      end

      context "when the order in the address state" do
        context 'when landing to address page' do
          let!(:order) do 
            create(:order_with_line_items, state: 'address', user_id: user.id, bill_address: nil, ship_address: nil)
          end
          let(:user) { create(:user_with_addresses) }

          it "tries to associate user addresses to order" do
            patch spree.update_checkout_path(state: 'address')

            expect(order.reload.ship_address).to be_present
            expect(order.reload.bill_address).to be_present
          end
        end

        context "with a billing and shipping address" do
          subject do
            patch spree.update_checkout_path(
              state: 'address',
              order: {
                bill_address_attributes: order.bill_address.attributes.except("created_at", "updated_at").compact,
                ship_address_attributes: order.ship_address.attributes.except("created_at", "updated_at").compact,
                use_billing: false
              }
            )
          end

          it "doesn't change bill address" do
            expect {
              subject
            }.not_to change { order.reload.ship_address.id }
          end

          it "doesn't change ship address" do
            expect {
              subject
            }.not_to change { order.reload.bill_address.id }
          end
        end
      end

      # This is the only time that we need the 'set_payment_parameters_amount'
      # controller code, because otherwise the transition to 'confirm' will
      # trigger the 'add_store_credit_payments' transition code which will do
      # the same thing here.
      # Perhaps we can just remove 'set_payment_parameters_amount' entirely at
      # some point?
      context "when there is a checkout step between payment and confirm", partial_double_verification: false do
        before do
          @old_checkout_flow = Spree::Order.checkout_flow
          Spree::Order.class_eval do
            insert_checkout_step :new_step, after: :payment
          end
        end

        after do
          Spree::Order.checkout_flow(&@old_checkout_flow)
        end

        let(:order) { create(:order_with_line_items) }
        let(:payment_method) { create(:credit_card_payment_method) }

        let(:params) do
          {
            state: 'payment',
            order: {
              payments_attributes: [
                {
                  payment_method_id: payment_method.id.to_s,
                  source_attributes: attributes_for(:credit_card)
                }
              ]
            }
          }
        end

        before do
          order.update! user: user
          3.times { order.next! } # should put us in the payment state
        end

        it 'sets the payment amount' do
          patch spree.update_checkout_path(params)
          order.reload
          expect(order.state).to eq('new_step')
          expect(order.payments.size).to eq(1)
          expect(order.payments.first.amount).to eq(order.total)
        end
      end

      context "when in the payment state" do
        let(:order) { create(:order_with_line_items) }
        let(:payment_method) { create(:credit_card_payment_method) }

        let(:params) do
          {
            state: 'payment',
            order: {
              payments_attributes: [
                {
                  payment_method_id: payment_method.id.to_s,
                  source_attributes: attributes_for(:credit_card)
                }
              ]
            }
          }
        end

        before { order.update! user: user, state: 'payment' }

        context 'with a permitted payment method' do
          it 'sets the payment amount' do
            patch spree.update_checkout_path(params)
            order.reload
            expect(order.state).to eq('confirm')
            expect(order.payments.size).to eq(1)
            expect(order.payments.first.amount).to eq(order.total)
          end
        end

        context 'with an unpermitted payment method' do
          before { payment_method.update!(available_to_users: false) }

          it 'sets the payment amount' do
            expect {
              patch spree.update_checkout_path(params)
            }.to raise_error(ActiveRecord::RecordNotFound)

            expect(order.state).to eq('payment')
            expect(order.payments).to be_empty
          end
        end
      end

      context "when in the confirm state" do
        before do
          order.update! user: user, state: 'confirm'
          # An order requires a payment to reach the complete state
          # This is because payment_required? is true on the order
          create(:payment, amount: order.total, order: order)
          order.create_proposed_shipments
          order.payments.reload
        end

        # This inadvertently is a regression test for https://github.com/spree/spree/issues/2694
        it "redirects to the order view" do
          patch spree.update_checkout_path(state: "confirm")
          expect(response).to redirect_to spree.order_path(order)
        end

        it "populates the flash message" do
          patch spree.update_checkout_path(state: "confirm")
          expect(flash.notice).to eq(I18n.t('spree.order_processed_successfully'))
        end

        it "removes completed order from current_order" do
          patch spree.update_checkout_path(state: "confirm")
          expect(assigns(:current_order)).to be_nil
          expect(assigns(:order)).to eql controller.current_order
        end
      end
    end

    context "save unsuccessful" do
      before do
        order.update! user: user
      end

      it "does not assign order" do
        patch spree.update_checkout_path(state: "address", email: '')
        expect(assigns[:order]).not_to be_nil
      end

      it "renders the edit template" do
        order.line_items.destroy_all
        patch spree.update_checkout_path(state: "address",  email: '')
        expect(response).to redirect_to(spree.cart_path)
      end
    end

    context "when current_order is nil" do
      it "should not change the state if order is completed" do
        pending('review this test')
        expect(order).not_to receive(:update_attribute)
        post :update, params: { state: "confirm" }
      end

      it "redirects to the cart_path" do
        pending('review this test')
        post :update, params: { state: "confirm" }
        expect(response).to redirect_to spree.cart_path
      end
    end

    context "Spree::Core::GatewayError" do
      pending('review this test') do
        before do
          order.update! user: user
          allow(order).to receive(:next).and_raise(Spree::Core::GatewayError.new("Invalid something or other."))
          post :update, params: { state: "address" }
        end

        it "should render the edit template and display exception message" do
        
          expect(response).to render_template :edit
          expect(flash.now[:error]).to eq(I18n.t('spree.spree_gateway_error_flash_for_checkout'))
          expect(assigns(:order).errors[:base]).to include("Invalid something or other.")
        end
      end
    end

    context "fails to transition from address" do
      let(:order) do
        FactoryBot.create(:order_with_line_items).tap do |order|
          order.next!
          expect(order.state).to eq('address')
        end
      end

      before do
        allow(controller).to receive_messages current_order: order
        allow(controller).to receive_messages check_authorization: true
      end

      context "when the order is invalid" do
        pending('review this test') do
          before do
            allow(order).to receive_messages valid?: true, next: nil
            order.errors.add :base, 'Base error'
            order.errors.add :adjustments, 'error'
          end

          it "due to the order having errors" do
            put :update, params: { state: order.state, order: {} }
            expect(flash[:error]).to eq("Base error\nAdjustments error")
            expect(response).to redirect_to(spree.checkout_state_path('address'))
          end
        end
      end

      context "when the country is not a shippable country" do
        let(:foreign_address) { create(:address, country_iso_code: "CA") }

        before do
          order.update! user: user
          order.update(shipping_address: foreign_address)
        end

        it "redirects due to no available shipping rates for any of the shipments" do
          patch spree.update_checkout_path(state: "address")
          expect(request.flash.to_h['error']).to eq(I18n.t('spree.items_cannot_be_shipped'))
          expect(response).to redirect_to(spree.checkout_state_path('address'))
        end
      end
    end

    context "when GatewayError is raised" do
      let(:order) do
        FactoryBot.create(:order_with_line_items).tap do |order|
          until order.state == 'payment'
            order.next!
          end
          # So that the confirmation step is skipped and we get straight to the action.
          payment_method = FactoryBot.create(:simple_credit_card_payment_method)
          payment = FactoryBot.create(:payment, payment_method: payment_method, amount: order.total)
          order.payments << payment
          order.next!
        end
      end

      before do
        allow(controller).to receive_messages current_order: order
        allow(controller).to receive_messages check_authorization: true
      end

      it "fails to transition from payment to complete" do
        pending('review this test: there are another GatewayError test')
        allow_any_instance_of(Spree::Payment).to receive(:process!).and_raise(Spree::Core::GatewayError.new(I18n.t('spree.payment_processing_failed')))
        put :update, params: { state: order.state, order: {} }
        expect(flash[:error]).to eq(I18n.t('spree.payment_processing_failed'))
      end
    end

    context "when InsufficientStock error is raised" do
      before { order.update! user: user }

      context "when the order has no shipments" do
        let(:order) { Spree::TestingSupport::OrderWalkthrough.up_to(:address) }
        let(:out_of_stock_items) { order.insufficient_stock_lines.collect(&:name).to_sentence }

        before do
          Spree::StockItem.update_all(count_on_hand: 0, backorderable: false)
        end

        pending('changed from testing the insufficient_stock_error rescue to the :ensure_sufficient_stock_lines before filter which happen before') do
          it "redirects the customer to the cart page with an error message" do
            patch spree.update_checkout_path(state: "address")
            expect(request.flash.to_h['error']).to eq(I18n.t('spree.inventory_error_flash_for_insufficient_quantity', names: out_of_stock_items))
            expect(response).to redirect_to(spree.cart_path)
          end
        end
      end

      context "when the order has shipments" do
        let(:order) { Spree::TestingSupport::OrderWalkthrough.up_to(:payment) }

        context "when items become somehow not available anymore" do
          before { Spree::StockItem.update_all(count_on_hand: 0, backorderable: false) }

          it "redirects the customer to the address checkout page with an error message" do
            pending('review this test to decide if test the insufficient stock rescue or before filter')
            patch spree.update_checkout_path(state: "address")
            error = I18n.t('spree.inventory_error_flash_for_insufficient_shipment_quantity', unavailable_items: order.products.first.name)
            expect(flash[:error]).to eq(error)
            expect(response).to redirect_to(spree.checkout_state_path(state: :address))
          end
        end
      end
    end
  end

  context "When last inventory item has been purchased" do
    let(:order) { create(:order_with_line_items) }

    before do
      ApplicationController.allow_forgery_protection = false
      order.update(user: user)
      stub_spree_preferences(track_inventory_levels: true)
    end

    context "when back orders are not allowed" do
      before do
        Spree::StockItem.update_all(count_on_hand: 0, backorderable: false)
        patch spree.update_checkout_path(state: "payment")
      end

      it "redirects to cart" do
        expect(response).to redirect_to spree.cart_path
      end

      it "should set flash message for no inventory" do
        pending('review insufficient stocks test')
        expect(flash[:error]).to eq("Amazing Item became unavailable.")
      end
    end
  end

  context "order doesn't have a delivery step" do
    let(:order) { create(:order_with_totals) }

    before do
      allow(order).to receive_messages(checkout_steps: ["cart", "address", "payment"])
      allow(order).to receive_messages state: "address"
      allow(controller).to receive_messages check_authorization: true
    end

    it "doesn't set a default shipping address on the order" do
      pending('find a way to test this')
      expect(order).to_not receive(:ship_address=)
      post :update, params: { state: order.state, order: { bill_address_attributes: address_params } }
    end

    it "doesn't remove unshippable items before payment" do
      pending('find a way to test this')
      expect {
        post :update, params: { state: "payment" }
      }.to_not change { order.line_items }
    end
  end

  it "does remove unshippable items before payment" do
    pending('this is related to the out of stock items')
    allow(order).to receive_messages payment_required?: true
    allow(controller).to receive_messages check_authorization: true

    expect {
      post :update, params: { state: "payment" }
    }.to change { order.line_items.to_a.size }.from(1).to(0)
  end

  
  context 'trying to apply a coupon code' do
    let(:order) { create(:order_with_line_items, state: 'payment', guest_token: 'a token') }
    let(:coupon_code) { "coupon_code" }

    pending('This is not testing anything.') do
      before { cookies.signed[:guest_token] = order.guest_token }

      context "when coupon code is empty" do
        let(:coupon_code) { "" }

        it 'does not try to apply coupon code' do
      
          expect(Spree::PromotionHandler::Coupon).not_to receive :new

          put :update, params: { state: order.state, order: { coupon_code: coupon_code } }

          expect(response).to redirect_to(spree.checkout_state_path('confirm'))
        end
      end
    end
  end
end
