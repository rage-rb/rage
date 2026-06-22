# frozen_string_literal: true

RSpec.describe Rage::Daemon do
  subject { daemon.__perform }

  let(:validator) { spy }

  before :all do
    Fiber.set_scheduler(Rage::FiberScheduler.new)
  end

  after :all do
    Fiber.set_scheduler(nil)
  end

  before do
    allow_any_instance_of(daemon).to receive(:validator).and_return(validator)
    allow(Rage).to receive(:logger).and_return(Rage::Logger.new(STDERR))
  end

  context "with a single-action perform" do
    let(:daemon) do
      Class.new(Rage::Daemon) do
        def perform
          validator.perform
          Rage::Daemon::Stop
        end
      end
    end

    it "calls perform" do
      within_reactor do
        subject
        -> { expect(validator).to have_received(:perform) }
      end
    end

    it "doesn't restart the daemon" do
      within_reactor do
        subject
        sleep 1
        -> { expect(validator).to have_received(:perform) }
      end
    end
  end

  context "with cleanup" do
    context "when daemon stops" do
      let(:daemon) do
        Class.new(Rage::Daemon) do
          def perform
            Rage::Daemon::Stop
          end

          def cleanup
            validator.cleanup
          end
        end
      end

      it "calls cleanup" do
        within_reactor do
          subject
          -> { expect(validator).to have_received(:cleanup) }
        end
      end
    end

    context "when daemon raises" do
      let(:daemon) do
        Class.new(Rage::Daemon) do
          def perform
            raise ZeroDivisionError
          end

          def cleanup
            validator.cleanup
          end
        end
      end

      it "calls cleanup" do
        within_reactor do
          subject
          -> { expect(validator).to have_received(:cleanup).at_least(:once) }
        end
      end

      it "reports the error" do
        within_reactor do
          expect(Rage.logger).to receive(:error).with(/Daemon failed with exception: ZeroDivisionError/).at_least(:once)
          expect(Rage::Errors).to receive(:report).with(ZeroDivisionError).at_least(:once)
          subject
          -> {}
        end
      end
    end

    context "when server stops" do
      before do
        allow(Iodine).to receive(:on_state).with(:start_shutdown).and_yield
      end

      let(:daemon) do
        Class.new(Rage::Daemon) do
          def perform
          end

          def cleanup
            validator.cleanup
          end
        end
      end

      it "calls cleanup" do
        within_reactor do
          subject
          -> { expect(validator).to have_received(:cleanup) }
        end
      end
    end

    context "when cleanup raises" do
      let(:daemon) do
        Class.new(Rage::Daemon) do
          def perform
            Rage::Daemon::Stop
          end

          def cleanup
            raise ZeroDivisionError
          end
        end
      end

      it "reports the error" do
        within_reactor do
          expect(Rage.logger).to receive(:error).with(/Cleanup hook failed with exception: ZeroDivisionError/)
          expect(Rage::Errors).to receive(:report).with(ZeroDivisionError)
          expect { subject }.not_to raise_error
          -> {}
        end
      end
    end
  end

  context "when initialize raises" do
    let(:daemon) do
      Class.new(Rage::Daemon) do
        def initialize
          raise ZeroDivisionError
        end

        def perform
        end
      end
    end

    it "reports the error" do
      within_reactor do
        -> do
          expect(Rage.logger).to receive(:error).with(/Daemon failed with exception: ZeroDivisionError/)
          expect(Rage::Errors).to receive(:report).with(ZeroDivisionError)
          expect { subject }.not_to raise_error
          -> {}
        end
      end
    end
  end

  context "with restart on exception" do
    let(:daemon) do
      Class.new(Rage::Daemon) do
        def perform
          validator.perform(@state)
          @state = rand
        end
      end
    end

    it "creates a new instance" do
      within_reactor do
        subject
        sleep 1

        -> do
          expect(validator).to have_received(:perform).at_least(:once)
          expect(validator).not_to have_received(:perform).with(satisfy { |c| !c.nil? })
        end
      end
    end
  end

  context "with backoff" do
    let(:daemon) do
      Class.new(Rage::Daemon) do
        def perform
          raise ZeroDivisionError
        end
      end
    end

    before do
      original_sleep = daemon.method(:sleep)

      allow(daemon).to receive(:sleep) do |timeout|
        timeouts << timeout
        original_sleep.call(timeout)
      end
    end

    let(:timeouts) { [] }

    it "sleeps with increasing intervals" do
      within_reactor do
        subject
        sleep 1

        -> do
          expect(timeouts.sort).to eq(timeouts)
        end
      end
    end
  end

  context "with exclusive daemon" do
    let(:daemon) do
      Class.new(Rage::Daemon) do
        exclusive

        def perform
          validator.perform
        end
      end
    end

    before do
      allow(daemon).to receive(:name).and_return(:ExclusiveTestDaemon)
    end

    it "starts the daemon in one worker" do
      within_reactor do
        perform_block = nil
        expect(Rage::Internal).to receive(:pick_a_worker).with(purpose: /ExclusiveTestDaemon/) do |&block|
          perform_block = block
        end

        subject
        expect(validator).not_to have_received(:perform)

        perform_block.call

        -> { expect(validator).to have_received(:perform).at_least(:once) }
      end
    end
  end
end
