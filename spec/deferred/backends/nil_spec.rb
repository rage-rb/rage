# frozen_string_literal: true

RSpec.describe Rage::Deferred::Backends::Nil do
  subject(:backend) { described_class.new }

  it "retains traversal and removal behavior" do
    expect(backend).to respond_to(:each_dead_task, :remove_dead_tasks)
    expect(backend.enum_for(:each_dead_task).to_a).to eq([])
    expect(backend.remove_dead_tasks("missing-id")).to eq(0)
  end
end
