ActiveRecord::Schema.define do
  create_table :tenants, force: true do |t|
    t.string :commerce7_tenant_id, null: false
    t.datetime :activated_at
    t.datetime :deactivated_at
    t.json :raw_activation_payload, default: {}

    t.timestamps
  end
  add_index :tenants, :commerce7_tenant_id, unique: true

  # Stands in for a host app's own tenant-scoped tables (e.g. ClubMember,
  # OrderSummary) — exists so the purge job spec can prove Current.tenant
  # actually needs to be set for a dependent: :destroy cascade to work
  # against a real FK constraint, the same gotcha the real app hit.
  create_table :notes, force: true do |t|
    t.references :tenant, null: false, foreign_key: true
    t.string :body

    t.timestamps
  end

  create_table :audit_events, force: true do |t|
    t.string :event_type, null: false
    t.boolean :success, null: false
    t.string :actor
    t.string :commerce7_tenant_id
    t.string :origin_ip
    t.json :metadata, default: {}

    t.timestamps
  end
end
