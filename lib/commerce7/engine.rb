# frozen_string_literal: true

module Commerce7
  # Adds this gem's app/{controllers,models/concerns,jobs,services,views}
  # to the host app's autoload/eager-load and view paths — the standard
  # Rails::Engine subclassing convention. Deliberately not isolated
  # (no `isolate_namespace`) and mounts no routes of its own: a host app
  # keeps declaring its own config/routes.rb entries exactly as it would
  # for any in-app controller, just pointing at these gem-provided classes
  # (e.g. `post "activate", to: "commerce7/activations#create"`). That keeps
  # the URLs Commerce7's Developer Center has registered (Install/Uninstall
  # URLs, the App Extension iframe src) stable and host-controlled.
  class Engine < ::Rails::Engine
    engine_name "commerce7"
  end
end
