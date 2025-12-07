# frozen_string_literal: true

RSpec.describe Rage::Deferred do
  describe ".__load_tasks" do
    let(:backend) { instance_double("Rage::Deferred::Backend") }
    let(:queue) { instance_double(Rage::Deferred::Queue) }

    before do
      allow(Rage::Deferred).to receive(:__backend).and_return(backend)
      allow(Rage::Deferred).to receive(:__queue).and_return(queue)
      allow(queue).to receive(:schedule)
    end

    context "when there are no pending tasks" do
      it "does not schedule any tasks" do
        allow(backend).to receive(:pending_tasks).and_return([])
        Rage::Deferred.__load_tasks
        expect(queue).not_to have_received(:schedule)
      end
    end

    context "when there are pending tasks" do
      let(:current_time) { Time.now }
      let(:task1) { ["id1", "wrapper1", nil] }
      let(:task2) { ["id2", "wrapper2", current_time.to_i + 10] }
      let(:task3) { ["id3", "wrapper3", current_time.to_i - 5] }

      before do
        allow(Time).to receive(:now).and_return(current_time)
        allow(backend).to receive(:pending_tasks).and_return([task1, task2, task3])
        Rage::Deferred.__load_tasks
      end

      it "schedules tasks with correct arguments" do
        expect(queue).to have_received(:schedule).with("id1", "wrapper1", publish_in: nil)
        expect(queue).to have_received(:schedule).with("id2", "wrapper2", publish_in: 10)
        expect(queue).to have_received(:schedule).with("id3", "wrapper3", publish_in: -5)
      end
    end
  end

  describe ".wrap" do
    let(:instance) { double("instance") }
    let(:proxy) { instance_double(Rage::Deferred::Proxy) }

    before do
      allow(Rage::Deferred::Proxy).to receive(:new).and_return(proxy)
    end

    it "creates a proxy object" do
      expect(Rage::Deferred::Proxy).to receive(:new).with(instance, delay: nil, delay_until: nil)
      described_class.wrap(instance)
    end

    it "returns the proxy object" do
      expect(described_class.wrap(instance)).to eq(proxy)
    end

    it "passes the delay option to the proxy" do
      expect(Rage::Deferred::Proxy).to receive(:new).with(instance, delay: 10, delay_until: nil)
      described_class.wrap(instance, delay: 10)
    end

    it "passes the delay_until option to the proxy" do
      time = Time.now
      expect(Rage::Deferred::Proxy).to receive(:new).with(instance, delay: nil, delay_until: time)
      described_class.wrap(instance, delay_until: time)
    end
  end

  describe ".__middleware_chain" do
    it "initializes middleware chain" do
      allow(Rage.config.deferred.enqueue_middleware).to receive(:objects).and_return(:test_enqueue_middleware_objects)
      allow(Rage.config.deferred.perform_middleware).to receive(:objects).and_return(:test_perform_middleware_objects)

      expect(Rage::Deferred::MiddlewareChain).to receive(:new).with(
        enqueue_middleware: :test_enqueue_middleware_objects,
        perform_middleware: :test_perform_middleware_objects
      )

      described_class.__middleware_chain
    end
  end
end
