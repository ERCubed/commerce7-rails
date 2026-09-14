class Note < ActiveRecord::Base
  belongs_to :tenant

  default_scope { Current.tenant ? where(tenant_id: Current.tenant.id) : none }
end
