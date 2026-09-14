# frozen_string_literal: true

module Commerce7
  # Include in the host app's own tenant model (see
  # Commerce7.configuration.tenant_class_name) to get the activate/
  # deactivate lifecycle Commerce7::ActivationsController,
  # DeactivationsController, ExtensionController, and WebhooksController all
  # depend on. Expects the model to have commerce7_tenant_id,
  # activated_at, deactivated_at, and raw_activation_payload columns — see
  # Commerce7::Generators::InstallGenerator for a migration that adds them.
  #
  # raw_activation_payload carries PII (the installing staff member's name/
  # email, per Commerce7's activation docs) — add `encrypts
  # :raw_activation_payload` in the including model.
  module TenantConcern
    extend ActiveSupport::Concern

    # Commerce7's app security policy requires customer data deleted within
    # 30 days of app termination — see Commerce7::PurgeDeactivatedTenantsJob,
    # which hard-deletes any tenant still deactivated after this window.
    # Kept short of 30 days deliberately: a tenant reactivated via
    # .activate! before this elapses keeps all its data.
    DATA_RETENTION_DAYS = 30

    included do
      validates :commerce7_tenant_id, presence: true, uniqueness: true

      scope :active, -> { where(deactivated_at: nil) }
      scope :pending_deletion, -> { where.not(deactivated_at: nil).where(deactivated_at: ..DATA_RETENTION_DAYS.days.ago) }
    end

    class_methods do
      # Handles both first install and a reinstall of a previously
      # deactivated tenant (find_or_initialize_by, not create!) —
      # activation always clears deactivated_at, matching Commerce7
      # sending an activation POST either way.
      def activate!(commerce7_tenant_id:, payload:)
        tenant = find_or_initialize_by(commerce7_tenant_id: commerce7_tenant_id)
        tenant.update!(activated_at: Time.current, deactivated_at: nil, raw_activation_payload: payload)
        tenant
      end
    end

    def active?
      deactivated_at.nil?
    end

    # Soft-deactivates, never deletes — an uninstall may be followed by a
    # reinstall (see .activate!), and this app's synced data shouldn't
    # vanish just because the app was temporarily removed.
    def deactivate!
      update!(deactivated_at: Time.current)
    end
  end
end
