# frozen_string_literal: true

RSpec.describe Rage::Ext::ActiveRecord::ConnectionPool do
  describe ".with_connection" do
    it "works" do
      expect(1 + 1).to eq(2)
    end
  end
end
