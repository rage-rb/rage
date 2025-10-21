# frozen_string_literal: true

module EventsLoggerSpec
  Event1 = Data.define

  class Subscriber1
    include Rage::Events::Subscriber
    subscribe_to Event1

    def handle(_)
      Rage.logger.info "test"
    end
  end

  Event2 = Data.define

  class Subscriber2Base
    include Rage::Events::Subscriber
  end

  class Subscriber2 < Subscriber2Base
    subscribe_to Event2

    def handle(_)
      Rage.logger.info "test"
    end
  end

  Event3_1 = Data.define
  Event3_2 = Data.define

  class Subscriber3_1
    include Rage::Events::Subscriber
    subscribe_to Event3_1

    def handle(_)
      Rage.logger.info "test 1"
      Rage::Events.publish(Event3_2.new)
      Rage.logger.info "test 3"
    end
  end

  class Subscriber3_2
    include Rage::Events::Subscriber
    subscribe_to Event3_2

    def handle(_)
      Rage.logger.info "test 2"
    end
  end
end

RSpec.describe Rage::Events do
  before do
    allow(Rage).to receive(:logger).and_return(Rage::Logger.new(output))
  end

  let(:output) { StringIO.new }

  context "with plain subscriber" do
    it "adds log context" do
      expect(output).to receive(:write) do |log|
        expect(log).to include("subscriber=EventsLoggerSpec::Subscriber1")
        expect(log).to include("message=test")
      end

      described_class.publish(EventsLoggerSpec::Event1.new)
    end
  end

  context "with inherited subscriber" do
    it "adds log context" do
      expect(output).to receive(:write) do |log|
        expect(log).to include("subscriber=EventsLoggerSpec::Subscriber2")
        expect(log).to include("message=test")
      end

      described_class.publish(EventsLoggerSpec::Event2.new)
    end
  end

  context "with nested publish calls" do
    it "adds log context" do
      expect(output).to receive(:write) do |log|
        expect(log).to include("subscriber=EventsLoggerSpec::Subscriber3_1")
        expect(log).to include("message=test 1")
      end

      expect(output).to receive(:write) do |log|
        expect(log).to include("subscriber=EventsLoggerSpec::Subscriber3_2")
        expect(log).to include("message=test 2")
      end

      expect(output).to receive(:write) do |log|
        expect(log).to include("subscriber=EventsLoggerSpec::Subscriber3_1")
        expect(log).to include("message=test 3")
      end

      described_class.publish(EventsLoggerSpec::Event3_1.new)
    end
  end
end
