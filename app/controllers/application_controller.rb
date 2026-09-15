class ApplicationController < ActionController::API
  include Pundit::Authorization
  include Pagy::Backend
  include Authenticatable

  rescue_from Pundit::NotAuthorizedError, with: :render_forbidden
  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
  # Malformed params must be a clean 400, not a 500. Rails maps only the base
  # ParseError by exact class name, so its ParamBuilder subclasses
  # (ParameterTypeError / InvalidParameterError) would otherwise 500.
  rescue_from ActionDispatch::ParamError, with: :render_bad_request

  before_action :set_active_storage_url_options

  private

  def set_active_storage_url_options
    ActiveStorage::Current.url_options = {
      host: request.host, port: request.port, protocol: request.protocol
    }
  end

  # ---- Rendering ----------------------------------------------------------
  # Lifted from hatiwal-api so the two APIs answer in the same shape and the
  # mobile client's plumbing transfers.

  def render_blue(serializer, record, view: :default, status: :ok, options: {})
    render json: {
      serializer.model_name.singular => serializer.render_as_hash(record, view: view, **options)
    }, status: status
  end

  # For small fixed-size lists where pagination would be noise.
  def render_blue_collection(serializer, collection, view: :default, status: :ok, options: {})
    render json: {
      serializer.model_name.plural => serializer.render_as_hash(collection, view: view, **options)
    }, status: status
  end

  MAX_PAGE_SIZE = 100

  # JSON:API-style `page[number]` / `page[size]`, size clamped. Both clients
  # send a size and expect it honoured, so it must not be silently ignored.
  def pagy_page_options
    raw = params[:page]
    if raw.is_a?(ActionController::Parameters)
      number = raw[:number].to_i
      size = raw[:size].to_i
    else
      number = raw.to_i
      size = 0
    end

    options = { page: number < 1 ? 1 : number }
    # Pagy 8.x's per-page var is `:items`; pass it explicitly or the size is
    # ignored.
    options[:items] = size.clamp(1, MAX_PAGE_SIZE) if size.positive?
    options
  end

  def paginate_blue(serializer, collection, extra: {})
    pagy, records = pagy(collection, **pagy_page_options)

    render json: {
      serializer.model_name.plural => serializer.render_as_hash(
        records, view: extra[:view] || :default, **extra.except(:view)
      ),
      meta: { pagination: pagination_meta(pagy) }
    }
  end

  def pagination_meta(pagy)
    {
      current_page: pagy.page, next_page: pagy.next, prev_page: pagy.prev,
      total_count: pagy.count, total_pages: pagy.pages
    }
  end

  # ---- Errors -------------------------------------------------------------
  # `code:` carries a stable machine-readable marker alongside the human text,
  # so a client with three locales renders its OWN copy rather than showing an
  # English sentence from the API. Pashto and Dari users must not be shown
  # English because the server wrote the message.

  def render_unprocessable_entity(record_or_message, code: nil)
    body = if record_or_message.respond_to?(:errors)
             { errors: record_or_message.errors.full_messages }
    else
             { error: record_or_message.to_s }
    end
    body[:code] = code if code.present?

    render json: body, status: :unprocessable_content
  end

  def render_not_found
    render json: { error: "Not found", code: "not_found" }, status: :not_found
  end

  def render_forbidden
    render json: { error: "Forbidden", code: "forbidden" }, status: :forbidden
  end

  def render_bad_request
    render json: { error: "Bad request", code: "bad_request" }, status: :bad_request
  end

  def render_ok(payload, status: :ok)
    render json: payload, status: status
  end
end
