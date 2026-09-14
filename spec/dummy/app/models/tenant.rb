class Tenant < ActiveRecord::Base
  include Commerce7::TenantConcern

  has_many :notes, dependent: :destroy
end
