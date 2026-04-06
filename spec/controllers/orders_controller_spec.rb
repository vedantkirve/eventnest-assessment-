require "rails_helper"

RSpec.describe Api::V1::OrdersController, type: :request do
  let(:organizer)   { create(:user, :organizer) }
  let(:attendee)    { create(:user) }
  let(:other_user)  { create(:user) }
  let(:event)       { create(:event, user: organizer, status: "published", starts_at: 2.weeks.from_now, ends_at: 2.weeks.from_now + 3.hours) }
  let(:tier)        { create(:ticket_tier, event: event, quantity: 100, sold_count: 0) }

  def auth_headers(user)
    token = user.generate_jwt
    { "Authorization" => "Bearer #{token}" }
  end

  describe "GET /api/v1/orders" do
    it "returns only the current user's orders" do
      own_order   = create(:order, user: attendee,   event: event)
      other_order = create(:order, user: other_user, event: event)

      get "/api/v1/orders", headers: auth_headers(attendee)

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)
      returned_ids = data.map { |o| o["id"] }

      expect(returned_ids).to include(own_order.id)
      expect(returned_ids).not_to include(other_order.id)
    end
  end

  describe "GET /api/v1/orders/:id" do
    it "returns the order when it belongs to the current user" do
      order = create(:order, user: attendee, event: event)

      get "/api/v1/orders/#{order.id}", headers: auth_headers(attendee)

      expect(response).to have_http_status(:ok)
    end

    it "returns 404 when the order belongs to a different user" do
      other_order = create(:order, user: other_user, event: event)

      get "/api/v1/orders/#{other_order.id}", headers: auth_headers(attendee)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/orders/:id/cancel" do
    it "cancels a pending order that belongs to the current user" do
      order = create(:order, user: attendee, event: event, status: "pending")

      post "/api/v1/orders/#{order.id}/cancel", headers: auth_headers(attendee)

      expect(response).to have_http_status(:ok)
      expect(order.reload.status).to eq("cancelled")
    end

    it "returns 404 and does not cancel when the order belongs to a different user" do
      other_order = create(:order, user: other_user, event: event, status: "pending")

      post "/api/v1/orders/#{other_order.id}/cancel", headers: auth_headers(attendee)

      expect(response).to have_http_status(:not_found)
      expect(other_order.reload.status).to eq("pending")
    end
  end
end
