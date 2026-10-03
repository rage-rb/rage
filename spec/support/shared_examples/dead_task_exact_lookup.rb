# frozen_string_literal: true

RSpec.shared_examples "a dead-task exact-lookup backend" do |empty:|
  it "returns nil for a missing exact id" do
    expect(backend.find_dead_task("missing-id")).to be_nil
  end

  if empty
    it "remains empty and side-effect free" do
      state = backend.instance_variables.to_h { |name| [name, backend.instance_variable_get(name)] }

      expect(backend.find_dead_task("1700000001-1-1")).to be_nil
      expect(backend.instance_variables.to_h { |name| [name, backend.instance_variable_get(name)] }).to eq(state)
    end
  else
    it "returns an existing record with the shared public shape" do
      expected = store_lookup_record(:existing)

      expect(backend.find_dead_task(lookup_id)).to eq(expected)
      expect(expected).to include(
        :id, :task_class, :attempts, :enqueued_at, :failed_at,
        :exception_class, :exception_message, :backtrace, :context
      )
    end

    it "returns the newest frame-valid duplicate" do
      expected = store_lookup_record(:duplicate)

      expect(backend.find_dead_task(lookup_id)).to eq(expected)
    end

    it "returns a schema-incompatible newer frame without falling back" do
      expected = store_lookup_record(:schema_incompatible_duplicate)

      expect(backend.find_dead_task(lookup_id)).to eq(expected)
    end
  end
end
