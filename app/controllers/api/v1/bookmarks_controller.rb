module Api
  module V1
    class BookmarksController < ApplicationController

      def index
        bookmarks = current_user.bookmarks.includes(:event).order(created_at: :desc)

        render json: bookmarks.map { |b|
          {
            id:         b.id,
            event_id:   b.event.id,
            title:      b.event.title,
            city:       b.event.city,
            starts_at:  b.event.starts_at,
            status:     b.event.status,
            bookmarked_at: b.created_at
          }
        }
      end

      def create
        event = Event.find(params[:event_id])

        unless current_user.attendee?
          return render json: { error: "Only attendees can bookmark events" }, status: :forbidden
        end

        bookmark = Bookmark.new(user: current_user, event: event)

        if bookmark.save
          render json: { id: bookmark.id, event_id: event.id, message: "Event bookmarked" }, status: :created
        else
          render json: { errors: bookmark.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def destroy
        bookmark = current_user.bookmarks.find(params[:id])
        bookmark.destroy
        head :no_content
      end
    end
  end
end
