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
    allow(daemon).to receive(:name).and_return(:TestDaemon)
    allow(Rage::Internal).to receive(:pick_a_worker).with(purpose: /TestDaemon/).and_yield

    allow_any_instance_of(daemon).to receive(:validator).and_return(validator)
    # writing to a real file descriptor from inside the reactor hands it over to Iodine,
    # which closes it once the reactor stops
    allow(Rage).to receive(:logger).and_return(Rage::Logger.new(StringIO.new))
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

    it "starts the daemon in one worker" do
      within_reactor do
        perform_block = nil
        expect(Rage::Internal).to receive(:pick_a_worker).with(purpose: /TestDaemon/) do |&block|
          perform_block = block
        end

        subject
        expect(validator).not_to have_received(:perform)

        perform_block.call

        -> { expect(validator).to have_received(:perform).at_least(:once) }
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
      let(:daemon) do
        Class.new(Rage::Daemon) do
          def perform
            sleep 10
          end

          def cleanup
            validator.cleanup
          end
        end
      end

      it "calls cleanup" do
        within_reactor do
          subject
          sleep 0.1
          Rage::Daemon.__stop_all
          running = daemon.__running?

          -> do
            expect(validator).to have_received(:cleanup).once
            expect(running).to be(false)
          end
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

  context "with worker-level daemon" do
    let(:daemon) do
      Class.new(Rage::Daemon) do
        scope :worker

        def perform
          validator.perform
        end
      end
    end

    it "doesn't use Rage::Internal.pick_a_worker" do
      within_reactor do
        expect(Rage::Internal).not_to receive(:pick_a_worker)
        subject

        -> { expect(validator).to have_received(:perform).at_least(:once) }
      end
    end
  end

  context "with incorrect scope level" do
    let(:daemon) do
      Class.new(Rage::Daemon) do
        def perform
        end
      end
    end

    it "raises an error" do
      expect { daemon.scope(:unknown) }.to raise_error(/Invalid scope level: :unknown/)
    end
  end

  context "with inheritance" do
    context "with inherited scope level" do
      let(:parent_daemon) do
        Class.new(Rage::Daemon) do
          scope :worker

          def perform
          end
        end
      end

      let(:daemon) do
        Class.new(parent_daemon) do
          def perform
          end
        end
      end

      it "inherits the scope level" do
        expect(daemon.__level).to eq(:worker)
      end
    end

    context "with overriden scope level" do
      let(:parent_daemon) do
        Class.new(Rage::Daemon) do
          scope :worker

          def perform
          end
        end
      end

      let(:daemon) do
        Class.new(parent_daemon) do
          scope :node

          def perform
          end
        end
      end

      it "inherits the scope level" do
        expect(daemon.__level).to eq(:node)
        expect(parent_daemon.__level).to eq(:worker)
      end
    end

    context "with set scope level" do
      let(:parent_daemon) do
        Class.new(Rage::Daemon) do
          def perform
          end
        end
      end

      let(:daemon) do
        Class.new(parent_daemon) do
          scope :worker

          def perform
          end
        end
      end

      it "sets the scope level independently" do
        expect(daemon.__level).to eq(:worker)
        expect(parent_daemon.__level).to be_nil
      end
    end
  end

  context "with reloading" do
    let(:events) { [] }

    let(:daemon) do
      Class.new(Rage::Daemon) do
        def perform
          loop do
            events << :old_tick
            sleep 0.05
          end
        end

        def cleanup
          events << :old_cleanup
        end
      end
    end

    let(:new_daemon) do
      Class.new(Rage::Daemon) do
        def perform
          events << :new_perform
          Rage::Daemon::Stop
        end
      end
    end

    let(:source_file) { Tempfile.new(["test_daemon", ".rb"]) }
    let(:klasses) { [daemon] }

    before do
      allow(new_daemon).to receive(:name).and_return(:TestDaemon)
      allow_any_instance_of(daemon).to receive(:events).and_return(events)
      allow_any_instance_of(new_daemon).to receive(:events).and_return(events)
      allow(Rage.env).to receive(:development?).and_return(true)
      allow(Object).to receive(:const_source_location).and_call_original
      allow(Object).to receive(:const_source_location).with(:TestDaemon).and_return([source_file.path, 1])
    end

    after do
      source_file.close!
    end

    # stub the registry inside the reactor so that the `on_start` hook doesn't start the daemon a second time
    def start_daemon
      allow(Rage.config.daemons).to receive(:klasses).and_return(klasses)
      daemon.__perform
      sleep 0.1
    end

    def edit_source_file
      time = Time.now + rand(10..1000)
      File.utime(time, time, source_file.path)
    end

    it "records the source file in development" do
      within_reactor do
        start_daemon
        -> do
          expect(daemon.__sources).to eq(source_file.path => File.mtime(source_file.path))
        end
      end
    end

    context "when the source file changed" do
      it "stops the previous version and starts the reloaded class" do
        within_reactor do
          start_daemon
          edit_source_file
          allow(Object).to receive(:const_get).and_call_original
          allow(Object).to receive(:const_get).with(:TestDaemon).and_return(new_daemon)

          Rage::Daemon.__reload_changed
          # capture the state before the reactor stops and shuts all daemons down
          old_running = daemon.__running?
          ticks_after_reload = events.count(:old_tick)
          sleep 0.2
          late_ticks = events.count(:old_tick) - ticks_after_reload
          cleanups = events.count(:old_cleanup)

          -> do
            expect(old_running).to be(false)
            expect(late_ticks).to eq(0)
            expect(cleanups).to eq(1)
            expect(events).to include(:new_perform)
            expect(events.index(:old_cleanup)).to be < events.index(:new_perform)
            expect(klasses).to eq([new_daemon])
          end
        end
      end

      it "keeps the previous version running if the reloaded file fails to load" do
        within_reactor do
          start_daemon
          edit_source_file
          allow(Object).to receive(:const_get).and_call_original
          allow(Object).to receive(:const_get).with(:TestDaemon).and_raise(SyntaxError, "unexpected end-of-input")
          expect(Rage::Errors).to receive(:report).with(instance_of(SyntaxError))

          Rage::Daemon.__reload_changed
          ticks_after_reload = events.count(:old_tick)
          sleep 0.2
          running = daemon.__running?
          new_ticks = events.count(:old_tick) - ticks_after_reload
          cleanups = events.count(:old_cleanup)

          -> do
            expect(running).to be(true)
            expect(new_ticks).to be > 0
            expect(cleanups).to eq(0)
            expect(klasses).to eq([daemon])
          end
        end
      end

      it "retries a failed reload only after the file changes again" do
        within_reactor do
          start_daemon
          edit_source_file
          allow(Object).to receive(:const_get).and_call_original
          allow(Object).to receive(:const_get).with(:TestDaemon).and_raise(SyntaxError, "unexpected end-of-input")
          allow(Rage::Errors).to receive(:report)

          Rage::Daemon.__reload_changed
          Rage::Daemon.__reload_changed # e.g. an unrelated file changed

          allow(Object).to receive(:const_get).with(:TestDaemon).and_return(new_daemon)
          edit_source_file
          Rage::Daemon.__reload_changed

          -> do
            expect(Rage::Errors).to have_received(:report).once
            expect(klasses).to eq([new_daemon])
          end
        end
      end

      it "keeps the previous version running if the reloaded constant is not a daemon" do
        within_reactor do
          start_daemon
          edit_source_file
          allow(Object).to receive(:const_get).and_call_original
          allow(Object).to receive(:const_get).with(:TestDaemon).and_return(Class.new)

          Rage::Daemon.__reload_changed
          running = daemon.__running?

          -> do
            expect(running).to be(true)
            expect(klasses).to eq([daemon])
          end
        end
      end

      it "doesn't restart the daemon if the class wasn't reloaded" do
        within_reactor do
          start_daemon
          edit_source_file
          allow(Object).to receive(:const_get).and_call_original
          allow(Object).to receive(:const_get).with(:TestDaemon).and_return(daemon)

          Rage::Daemon.__reload_changed
          running = daemon.__running?
          cleanups = events.count(:old_cleanup)

          -> do
            expect(running).to be(true)
            expect(cleanups).to eq(0)
          end
        end
      end

      it "restarts a daemon that returned Stop" do
        stopped_daemon = Class.new(Rage::Daemon) do
          def perform
            events << :stopped
            Rage::Daemon::Stop
          end
        end
        allow(stopped_daemon).to receive(:name).and_return(:TestDaemon)
        allow_any_instance_of(stopped_daemon).to receive(:events).and_return(events)
        allow(Rage::Internal).to receive(:pick_a_worker).and_yield

        within_reactor do
          allow(Rage.config.daemons).to receive(:klasses).and_return(klasses)
          klasses[0] = stopped_daemon
          stopped_daemon.__perform
          sleep 0.1
          stopped_running = stopped_daemon.__running?

          edit_source_file
          allow(Object).to receive(:const_get).and_call_original
          allow(Object).to receive(:const_get).with(:TestDaemon).and_return(new_daemon)
          Rage::Daemon.__reload_changed
          sleep 0.1

          -> do
            expect(stopped_running).to be(false)
            expect(events).to eq([:stopped, :new_perform])
            expect(klasses).to eq([new_daemon])
          end
        end
      end

      it "warns when the scope changes" do
        new_daemon.scope(:worker)
        logger = double(info: nil, warn: nil, error: nil)
        allow(Rage).to receive(:logger).and_return(logger)
        allow(logger).to receive(:with_context).and_yield

        within_reactor do
          start_daemon
          edit_source_file
          allow(Object).to receive(:const_get).and_call_original
          allow(Object).to receive(:const_get).with(:TestDaemon).and_return(new_daemon)
          Rage::Daemon.__reload_changed

          -> { expect(logger).to have_received(:warn).with(/Scope of daemon TestDaemon changed/) }
        end
      end
    end

    context "when the source file was deleted" do
      it "keeps the previous version running and warns once" do
        logger = double(info: nil, warn: nil, error: nil)
        allow(Rage).to receive(:logger).and_return(logger)
        allow(logger).to receive(:with_context).and_yield

        within_reactor do
          start_daemon
          File.unlink(source_file.path)
          allow(Object).to receive(:const_get).and_call_original

          Rage::Daemon.__reload_changed
          Rage::Daemon.__reload_changed
          running = daemon.__running?

          -> do
            expect(running).to be(true)
            expect(logger).to have_received(:warn).with(/was deleted/).once
            expect(Object).not_to have_received(:const_get).with(:TestDaemon)
          end
        end
      end
    end

    context "when the source file didn't change" do
      it "doesn't restart the daemon" do
        within_reactor do
          start_daemon
          allow(Object).to receive(:const_get).and_call_original

          Rage::Daemon.__reload_changed
          running = daemon.__running?

          -> do
            expect(Object).not_to have_received(:const_get).with(:TestDaemon)
            expect(running).to be(true)
            expect(klasses).to eq([daemon])
          end
        end
      end
    end

    context "with several daemons" do
      let(:other_daemon) do
        Class.new(Rage::Daemon) do
          scope :worker

          def perform
            sleep 10
          end
        end
      end

      let(:klasses) { [daemon, other_daemon] }

      it "restarts only the daemon whose source file changed" do
        allow(other_daemon).to receive(:name).and_return(:OtherDaemon)
        other_file = Tempfile.new(["other_daemon", ".rb"])
        allow(Object).to receive(:const_source_location).with(:OtherDaemon).and_return([other_file.path, 1])

        within_reactor do
          start_daemon
          other_daemon.__perform
          edit_source_file
          allow(Object).to receive(:const_get).and_call_original
          allow(Object).to receive(:const_get).with(:TestDaemon).and_return(new_daemon)

          Rage::Daemon.__reload_changed
          other_running = other_daemon.__running?

          -> do
            expect(Object).not_to have_received(:const_get).with(:OtherDaemon)
            expect(other_running).to be(true)
            expect(klasses).to eq([new_daemon, other_daemon])
          end
        end
      ensure
        other_file&.close!
      end
    end

    context "with an anonymous daemon" do
      let(:anonymous_daemon) do
        Class.new(Rage::Daemon) do
          scope :worker

          def perform
            events << :anonymous
            Rage::Daemon::Stop
          end
        end
      end

      it "starts the daemon in development" do
        allow_any_instance_of(anonymous_daemon).to receive(:events).and_return(events)

        within_reactor do
          anonymous_daemon.__perform
          sleep 0.1
          -> do
            expect(events).to eq([:anonymous])
            expect(anonymous_daemon.__sources).to be_nil
          end
        end
      end
    end

    context "with a real code loader" do
      let(:dir) { Dir.mktmpdir }
      let(:file) { File.join(dir, "zeitwerk_test_daemon.rb") }
      let(:loader) { Zeitwerk::Loader.new }

      def write_daemon(version)
        File.write(file, <<~RUBY)
          class ZeitwerkTestDaemon < Rage::Daemon
            scope :worker

            def perform
              $zeitwerk_test_daemon_events << :#{version}
              sleep 10
            end

            def cleanup
              $zeitwerk_test_daemon_events << :cleanup_#{version}
            end
          end
        RUBY

        time = Time.now + rand(10..1000)
        File.utime(time, time, file)
      end

      before do
        $zeitwerk_test_daemon_events = []
        allow(Object).to receive(:const_source_location).and_call_original
        write_daemon(:v1)
        loader.push_dir(dir)
        loader.enable_reloading
        loader.setup
      end

      after do
        loader.unload
        loader.unregister
        FileUtils.remove_entry(dir)
      end

      it "restarts the daemon with the updated code" do
        within_reactor do
          old_klass = ZeitwerkTestDaemon
          klasses = [old_klass]
          allow(Rage.config.daemons).to receive(:klasses).and_return(klasses)

          old_klass.__perform
          sleep 0.1

          write_daemon(:v2)
          loader.reload
          Rage::Daemon.__reload_changed
          sleep 0.1

          old_running = old_klass.__running?
          new_klass = klasses[0]
          new_running = new_klass.__running?
          events = $zeitwerk_test_daemon_events.dup

          -> do
            expect(old_klass.__sources.keys).to eq([file])
            expect(old_running).to be(false)
            expect(new_klass).not_to equal(old_klass)
            expect(new_running).to be(true)
            expect(events).to eq([:v1, :cleanup_v1, :v2])
          end
        end
      end

      context "with a parent daemon class and an included module" do
        let(:parent_file) { File.join(dir, "zeitwerk_parent_daemon.rb") }
        let(:module_file) { File.join(dir, "zeitwerk_daemon_helpers.rb") }
        let(:child_file) { File.join(dir, "zeitwerk_child_daemon.rb") }

        def write_parent(version)
          File.write(parent_file, <<~RUBY)
            class ZeitwerkParentDaemon < Rage::Daemon
              scope :worker

              def label
                :parent_#{version}
              end
            end
          RUBY
          bump(parent_file)
        end

        def write_module(version)
          File.write(module_file, <<~RUBY)
            module ZeitwerkDaemonHelpers
              def helper
                :helper_#{version}
              end
            end
          RUBY
          bump(module_file)
        end

        def bump(path)
          time = Time.now + rand(10..1000)
          File.utime(time, time, path)
        end

        before do
          File.unlink(file) # the default test daemon isn't used here
          write_parent(:v1)
          write_module(:v1)
          File.write(child_file, <<~RUBY)
            class ZeitwerkChildDaemon < ZeitwerkParentDaemon
              include ZeitwerkDaemonHelpers

              def perform
                $zeitwerk_test_daemon_events << [label, helper]
                sleep 10
              end
            end
          RUBY
          loader.reload
        end

        it "watches the files of the daemon and its parent daemon classes" do
          within_reactor do
            klass = ZeitwerkChildDaemon
            allow(Rage.config.daemons).to receive(:klasses).and_return([klass])
            klass.__perform
            sources = klass.__sources.keys
            watched = Rage::Daemon.__watched_files

            -> do
              expect(sources).to contain_exactly(child_file, parent_file)
              expect(watched).to include(child_file, parent_file)
              expect(watched).not_to include(module_file)
            end
          end
        end

        it "restarts the daemon when its parent class changes" do
          within_reactor do
            klasses = [ZeitwerkChildDaemon]
            allow(Rage.config.daemons).to receive(:klasses).and_return(klasses)
            klasses[0].__perform
            sleep 0.1

            write_parent(:v2)
            loader.reload
            Rage::Daemon.__reload_changed
            sleep 0.1
            events = $zeitwerk_test_daemon_events.dup

            -> { expect(events).to eq([[:parent_v1, :helper_v1], [:parent_v2, :helper_v1]]) }
          end
        end

        it "doesn't restart the daemon when an included module changes" do
          within_reactor do
            klasses = [ZeitwerkChildDaemon]
            allow(Rage.config.daemons).to receive(:klasses).and_return(klasses)
            old_klass = klasses[0]
            old_klass.__perform
            sleep 0.1

            write_module(:v2)
            loader.reload
            Rage::Daemon.__reload_changed
            sleep 0.1
            events = $zeitwerk_test_daemon_events.dup
            running = old_klass.__running?

            -> do
              expect(events).to eq([[:parent_v1, :helper_v1]])
              expect(running).to be(true)
              expect(klasses).to eq([old_klass])
            end
          end
        end
      end

      it "keeps the previous version running if the updated file has a syntax error" do
        within_reactor do
          old_klass = ZeitwerkTestDaemon
          klasses = [old_klass]
          allow(Rage.config.daemons).to receive(:klasses).and_return(klasses)
          allow(Rage::Errors).to receive(:report)

          old_klass.__perform
          sleep 0.1

          File.write(file, "class ZeitwerkTestDaemon < Rage::Daemon\n  def perform\n")
          File.utime(Time.now + 2000, Time.now + 2000, file)
          loader.reload
          Rage::Daemon.__reload_changed
          old_running = old_klass.__running?

          write_daemon(:v3)
          loader.reload
          Rage::Daemon.__reload_changed
          sleep 0.1
          new_klass = klasses[0]
          events = $zeitwerk_test_daemon_events.dup

          -> do
            expect(Rage::Errors).to have_received(:report).with(instance_of(SyntaxError)).once
            expect(old_running).to be(true)
            expect(new_klass).not_to equal(old_klass)
            expect(events).to eq([:v1, :cleanup_v1, :v3])
          end
        end
      end
    end
  end

  describe ".__boot" do
    let(:daemon) { Class.new(Rage::Daemon) }
    let(:code_loader) { double(reload_in_background: nil, reloadable?: true) }

    before do
      allow(Rage.config.daemons).to receive(:klasses).and_return([daemon])
      allow(daemon).to receive(:__perform)
      allow(Rage).to receive(:code_loader).and_return(code_loader)
      allow(Rage.config).to receive(:after_reload)
    end

    it "starts the registered daemons" do
      Rage::Daemon.__boot
      expect(daemon).to have_received(:__perform)
    end

    context "in development" do
      before { allow(Rage.env).to receive(:development?).and_return(true) }

      it "sets up reloading" do
        Rage::Daemon.__boot
        expect(Rage.config).to have_received(:after_reload)
        expect(code_loader).to have_received(:reload_in_background)
      end

      it "reports daemons that can't be reloaded" do
        allow(code_loader).to receive(:reloadable?).with(:TestDaemon).and_return(false)
        logger = double(info: nil)
        allow(Rage).to receive(:logger).and_return(logger)

        Rage::Daemon.__boot

        expect(logger).to have_received(:info).with(/TestDaemon is not managed by the code loader/)
      end

      it "doesn't set up reloading without daemons" do
        allow(Rage.config.daemons).to receive(:klasses).and_return([])
        Rage::Daemon.__boot
        expect(Rage.config).not_to have_received(:after_reload)
        expect(code_loader).not_to have_received(:reload_in_background)
      end
    end

    context "in production" do
      before { allow(Rage.env).to receive(:development?).and_return(false) }

      it "doesn't set up reloading" do
        Rage::Daemon.__boot
        expect(Rage.config).not_to have_received(:after_reload)
        expect(code_loader).not_to have_received(:reload_in_background)
      end
    end
  end
end
