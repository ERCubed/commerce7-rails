require "rails_helper"

RSpec.describe Commerce7::Webhooks do
  describe ".dispatch" do
    it "calls every handler registered for the (object, action) pair" do
      calls = []
      described_class.on("Club Membership", "Create", "Update") { |t, payload, actor| calls << [ t, payload, actor ] }

      handled = described_class.dispatch(object: "Club Membership", action: "Update", tenant: "t", payload: { "a" => 1 }, actor: "jason")

      expect(handled).to be true
      expect(calls).to eq([ [ "t", { "a" => 1 }, "jason" ] ])
    end

    it "returns false and calls nothing when no handler matches the object" do
      described_class.on("Club Membership", "Create") { |*| raise "should not run" }

      handled = described_class.dispatch(object: "Order", action: "Create", tenant: "t", payload: {}, actor: nil)

      expect(handled).to be false
    end

    it "returns false and calls nothing when the object matches but not the action" do
      described_class.on("Club Membership", "Create") { |*| raise "should not run" }

      handled = described_class.dispatch(object: "Club Membership", action: "Delete", tenant: "t", payload: {}, actor: nil)

      expect(handled).to be false
    end

    it "runs multiple handlers registered for the same pair" do
      calls = []
      described_class.on("Club Membership", "Delete") { calls << :first }
      described_class.on("Club Membership", "Delete") { calls << :second }

      described_class.dispatch(object: "Club Membership", action: "Delete", tenant: "t", payload: {}, actor: nil)

      expect(calls).to eq([ :first, :second ])
    end
  end

  describe ".reset!" do
    it "clears every registration" do
      described_class.on("Club Membership", "Create") { |*| raise "should not run" }

      described_class.reset!

      expect(described_class.dispatch(object: "Club Membership", action: "Create", tenant: "t", payload: {}, actor: nil)).to be false
    end
  end
end
