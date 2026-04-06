require "rails_helper"

RSpec.describe Api::V1::BookmarksController, type: :request do
  let(:organizer) { create(:user, :organizer) }
  let(:attendee)  { create(:user) }
  let(:event)     { create(:event, user: organizer, status: "published", starts_at: 2.weeks.from_now, ends_at: 2.weeks.from_now + 3.hours) }

  def auth_headers(user)
    token = user.generate_jwt
    { "Authorization" => "Bearer #{token}" }
  end

  describe "POST /api/v1/events/:event_id/bookmarks" do
    context "happy path" do
      it "allows an attendee to bookmark an event" do
        post "/api/v1/events/#{event.id}/bookmarks", headers: auth_headers(attendee)

        expect(response).to have_http_status(:created)
        expect(Bookmark.count).to eq(1)
        expect(Bookmark.last.user).to eq(attendee)
        expect(Bookmark.last.event).to eq(event)
      end
    end

    context "duplicate bookmark" do
      it "rejects a second bookmark for the same event by the same user" do
        create(:bookmark, user: attendee, event: event)

        post "/api/v1/events/#{event.id}/bookmarks", headers: auth_headers(attendee)

        expect(response).to have_http_status(:unprocessable_entity)
        data = JSON.parse(response.body)
        expect(data["errors"].first).to include("already bookmarked")
        expect(Bookmark.count).to eq(1)
      end
    end

    context "unauthorized role" do
      it "returns 403 when an organizer tries to bookmark an event" do
        post "/api/v1/events/#{event.id}/bookmarks", headers: auth_headers(organizer)

        expect(response).to have_http_status(:forbidden)
        expect(Bookmark.count).to eq(0)
      end
    end
  end

  describe "DELETE /api/v1/events/:event_id/bookmarks/:id" do
    it "allows an attendee to remove their own bookmark" do
      bookmark = create(:bookmark, user: attendee, event: event)

      delete "/api/v1/events/#{event.id}/bookmarks/#{bookmark.id}", headers: auth_headers(attendee)

      expect(response).to have_http_status(:no_content)
      expect(Bookmark.count).to eq(0)
    end

    it "returns 404 when trying to remove another user's bookmark" do
      other_attendee = create(:user)
      bookmark = create(:bookmark, user: other_attendee, event: event)

      delete "/api/v1/events/#{event.id}/bookmarks/#{bookmark.id}", headers: auth_headers(attendee)

      expect(response).to have_http_status(:not_found)
      expect(Bookmark.count).to eq(1)
    end
  end

  describe "GET /api/v1/bookmarks" do
    it "returns only the current user's bookmarks" do
      other_attendee = create(:user)
      own_bookmark   = create(:bookmark, user: attendee,       event: event)
      _other         = create(:bookmark, user: other_attendee, event: event)

      get "/api/v1/bookmarks", headers: auth_headers(attendee)

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)
      expect(data.length).to eq(1)
      expect(data.first["id"]).to eq(own_bookmark.id)
    end
  end

  describe "bookmark_count on GET /api/v1/events/:id" do
    before { create(:bookmark, user: attendee, event: event) }

    it "includes bookmark_count for the organizer who owns the event" do
      get "/api/v1/events/#{event.id}", headers: auth_headers(organizer)

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)
      expect(data).to have_key("bookmark_count")
      expect(data["bookmark_count"]).to eq(1)
    end

    it "does not include bookmark_count for an attendee" do
      get "/api/v1/events/#{event.id}", headers: auth_headers(attendee)

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)
      expect(data).not_to have_key("bookmark_count")
    end

    it "does not include bookmark_count for an organizer viewing another organizer's event" do
      other_organizer = create(:user, :organizer)

      get "/api/v1/events/#{event.id}", headers: auth_headers(other_organizer)

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)
      expect(data).not_to have_key("bookmark_count")
    end
  end
end
