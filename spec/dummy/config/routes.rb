Rails.application.routes.draw do
  namespace :commerce7 do
    post "activate", to: "activations#create", as: :activate
    post "deactivate", to: "deactivations#create", as: :deactivate
    post "webhooks", to: "webhooks#create", as: :webhooks
  end
end
