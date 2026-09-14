class AuditEvent < ActiveRecord::Base
  validates :event_type, presence: true
  validates :success, inclusion: { in: [ true, false ] }

  def self.record!(event_type:, success:, actor: nil, commerce7_tenant_id: nil, origin_ip: nil, metadata: {})
    create!(
      event_type: event_type,
      success: success,
      actor: actor,
      commerce7_tenant_id: commerce7_tenant_id,
      origin_ip: origin_ip,
      metadata: metadata
    )
  end
end
