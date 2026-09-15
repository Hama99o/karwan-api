# The courier's active job: one screen, one action at a time, both demand types.
class Api::V1::Couriers::JobsController < Api::V1::Couriers::BaseController
  KINDS = { "delivery" => Order, "ride" => Trip }.freeze

  before_action :set_job, only: %i[advance problem]

  # The single job in front of them. Not a list — a courier carries one job at a
  # time in v0, and returning an object rather than a collection keeps it that
  # way.
  def show
    job = active_job

    # `skip_authorization` rather than authorizing the CLASS. Passing `Order`
    # to a policy whose predicates read `record.customer_id` raises
    # NoMethodError on the class — there is nothing to authorise when there is
    # no record, and saying so explicitly keeps `verify_authorized` satisfied
    # without inventing a subject.
    if job.nil?
      skip_authorization
      return render_ok({ job: nil })
    end

    authorize job, :show?

    render_blue(Couriers::JobSerializer, job, view: :active)
  end

  def advance
    authorize @job, :show?

    job = Couriers::AdvanceJobService.new(
      job: @job, courier: current_user, step_key: params[:step_key]
    ).call

    render_blue(Couriers::JobSerializer, job.reload, view: :active)
  rescue Couriers::AdvanceJobService::NotYourJob => e
    render json: { error: e.message, code: "not_your_job" }, status: :forbidden
  rescue Couriers::AdvanceJobService::WrongStep => e
    render_unprocessable_entity(e.message, code: "wrong_step")
  rescue Couriers::AdvanceJobService::Error => e
    render_unprocessable_entity(e.message, code: "cannot_advance")
  end

  # The problem buttons: customer not answering, customer refused, unsafe.
  #
  # Every one records a reason and reaches admin, because the policies behind
  # them are money decisions — the platform absorbs a refusal and reimburses
  # the courier the same day — and a machine must not make those.
  def problem
    authorize @job, :show?

    reason = params[:reason].to_s
    reasons = @job.class.failure_reasons
    unless reasons.key?(reason)
      return render_unprocessable_entity("reason must be one of: #{reasons.keys.join(', ')}",
                                         code: "reason_required")
    end

    moved = @job.transition_to!(:failed, actor: current_user, actor_role: :courier, reason: reason)
    return render_unprocessable_entity("this job cannot be failed from #{@job.status}", code: "invalid_transition") unless moved

    @job.update!(failure_reason: reason)
    AuditLog.record!(action: "#{@job.class.name.downcase}.failed", actor: current_user,
                     actor_role: :courier, target: @job,
                     details: { reason: reason, note: "reported by the courier; needs a human" })

    render_blue(Couriers::JobSerializer, @job.reload, view: :active)
  end

  private

  # One live job across BOTH demand types — the courier pool is shared, so
  # "what am I doing right now" cannot be answered by one table.
  def active_job
    courier_jobs(Order).live.first || courier_jobs(Trip).live.first
  end

  def set_job
    klass = KINDS.fetch(params[:kind]) { raise ActiveRecord::RecordNotFound }
    @job = courier_jobs(klass).find(params[:id])
  end
end
