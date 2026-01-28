module AdminQueries
  class SystemEventsQuery
    def initialize(relation: SystemEvent.all)
      @relation = relation
    end

    # Supported params:
    # - kind
    # - status
    # - q (search in message and payload text)
    # - occurred_after (ISO date/time)
    # - occurred_before (ISO date/time)
    # - gem_name (looks up payload->>"gem_name" when present)
    # - branch (looks up payload->>"branch")
    def call(params)
      rel = @relation
      rel = rel.where(kind: params[:kind]) if params[:kind].present?
      rel = rel.where(status: params[:status]) if params[:status].present?

      if params[:q].present?
        q = "%#{params[:q]}%"
        rel = rel.where("message ILIKE ? OR CAST(payload AS text) ILIKE ?", q, q)
      end

      if params[:occurred_after].present?
        begin
          rel = rel.where("occurred_at >= ?", Time.parse(params[:occurred_after]))
        rescue ArgumentError
          # ignore invalid times
        end
      end

      if params[:occurred_before].present?
        begin
          rel = rel.where("occurred_at <= ?", Time.parse(params[:occurred_before]))
        rescue ArgumentError
          # ignore invalid times
        end
      end

      if params[:gem_name].present?
        # payload is a JSON column; use ->> when supported to extract text
        rel = rel.where("(payload ->> 'gem_name') = ?", params[:gem_name])
      end

      if params[:branch].present?
        rel = rel.where("(payload ->> 'branch') = ?", params[:branch])
      end

      rel.order(occurred_at: :desc)
    end
  end
end
