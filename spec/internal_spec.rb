# frozen_string_literal: true

RSpec.describe Rage::Internal do
  describe ".stream_name_for" do
    context "with a string" do
      it "returns the string as-is" do
        expect(described_class.stream_name_for("my-stream")).to eq("my-stream")
      end

      it "returns an empty string as-is" do
        expect(described_class.stream_name_for("")).to eq("")
      end
    end

    context "with a symbol" do
      it "converts to string" do
        expect(described_class.stream_name_for(:notifications)).to eq("notifications")
      end
    end

    context "with a numeric" do
      it "handles integers" do
        expect(described_class.stream_name_for(42)).to eq("42")
      end

      it "handles floats" do
        expect(described_class.stream_name_for(3.14)).to eq("3.14")
      end
    end

    context "with an object responding to id" do
      it "formats as ClassName:id" do
        user = double("User", id: 123, class: double(name: "User"))
        expect(described_class.stream_name_for(user)).to eq("User:123")
      end

      it "handles nil id" do
        user = double("User", id: nil, class: double(name: "User"))
        expect(described_class.stream_name_for(user)).to eq("User:")
      end

      it "handles namespaced classes" do
        admin = double("Admin::User", id: 1, class: double(name: "Admin::User"))
        expect(described_class.stream_name_for(admin)).to eq("Admin::User:1")
      end
    end

    context "with an array" do
      it "joins primitives with colons" do
        expect(described_class.stream_name_for([1, "chat", :messages])).to eq("1:chat:messages")
      end

      it "handles objects with id in array" do
        user = double("User", id: 42, class: double(name: "User"))
        expect(described_class.stream_name_for([user, "notifications"])).to eq("User:42:notifications")
      end

      it "handles multiple objects with id" do
        user = double("User", id: 1, class: double(name: "User"))
        room = double("Room", id: 5, class: double(name: "Room"))
        expect(described_class.stream_name_for([user, room, "messages"])).to eq("User:1:Room:5:messages")
      end

      it "handles single element array" do
        expect(described_class.stream_name_for(["single"])).to eq("single")
      end

      it "handles empty array" do
        expect(described_class.stream_name_for([])).to eq("")
      end
    end

    context "with invalid streamables" do
      it "raises ArgumentError for plain objects" do
        expect {
          described_class.stream_name_for(Object.new)
        }.to raise_error(ArgumentError, /Unable to generate stream name.*Object/)
      end

      it "raises ArgumentError for hash" do
        expect {
          described_class.stream_name_for({ key: "value" })
        }.to raise_error(ArgumentError, /Unable to generate stream name.*Array/)
      end

      it "raises ArgumentError for invalid element in array" do
        expect {
          described_class.stream_name_for([1, Object.new, "test"])
        }.to raise_error(ArgumentError, /Unable to generate stream name.*Object/)
      end

      it "returns empty string for nil" do
        expect(described_class.stream_name_for(nil)).to eq("")
      end
    end
  end

  describe ".pick_a_worker" do
    let(:on_start_callbacks) { [] }

    before do
      allow(Iodine).to receive(:running?).and_return(false)
      allow(Iodine).to receive(:on_state).with(:on_start) do |&block|
        on_start_callbacks << block
      end
    end

    after do
      described_class.instance_variable_set(:@lock_file, nil)
      described_class.instance_variable_set(:@worker_lock, nil)
    end

    it "registers a callback" do
      described_class.pick_a_worker { "work" }

      expect(Iodine).to have_received(:on_state).with(:on_start)
      expect(on_start_callbacks.size).to eq(1)
    end

    it "executes the block immediately when Iodine is already running" do
      allow(Iodine).to receive(:running?).and_return(true)
      executed = false
      described_class.pick_a_worker { executed = true }
      expect(executed).to be(true)
    end

    it "creates a lock file" do
      described_class.pick_a_worker { "work" }

      lock_file = described_class.instance_variable_get(:@lock_file)
      expect(File.exist?(lock_file.path)).to be(true)
    end

    it "uses provided lock_path instead of creating a new tempfile" do
      lock_path = Tempfile.new.path
      expect(Tempfile).not_to receive(:new)
      described_class.pick_a_worker(lock_path: lock_path) { "work" }
      on_start_callbacks.first.call
    end

    it "executes the block when lock is acquired" do
      executed = false
      described_class.pick_a_worker { executed = true }

      on_start_callbacks.first.call

      expect(executed).to be(true)
    end

    it "stores the worker lock when acquired" do
      described_class.pick_a_worker { "work" }

      on_start_callbacks.first.call

      worker_lock = described_class.instance_variable_get(:@worker_lock)
      expect(worker_lock).to be_a(File)
    end

    it "does not execute the block when lock cannot be acquired" do
      executed = false
      described_class.pick_a_worker { executed = true }

      lock_file = described_class.instance_variable_get(:@lock_file)

      external_lock = File.new(lock_file.path)
      external_lock.flock(File::LOCK_EX | File::LOCK_NB)

      on_start_callbacks.first.call
      expect(executed).to be(false)

      external_lock.flock(File::LOCK_UN)
      external_lock.close
    end

    it "allows only one worker to execute the block" do
      execution_count = 0
      described_class.pick_a_worker { execution_count += 1 }

      lock_file = described_class.instance_variable_get(:@lock_file)

      on_start_callbacks.first.call
      expect(execution_count).to eq(1)

      # Second worker tries but lock is held
      worker2_lock = File.new(lock_file.path)
      acquired = worker2_lock.flock(File::LOCK_EX | File::LOCK_NB)
      expect(acquired).to be(false)

      worker2_lock.close
    end
  end

  describe ".build_arguments" do
    subject { described_class.build_arguments(method, arguments) }

    context "with no parameters" do
      let(:method) { proc {} }
      let(:arguments) { { arg1: "true", arg2: "false" } }

      it "correctly builds arguments list" do
        expect(subject).to eq("")
      end
    end

    context "with a subset of parameters" do
      let(:method) { proc { |arg2:| } }
      let(:arguments) { { arg1: "true", arg2: "false" } }

      it "correctly builds arguments list" do
        expect(subject).to eq("arg2: false")
      end
    end

    context "with extra parameters" do
      let(:method) { proc { |arg2:, arg3:| } }
      let(:arguments) { { arg1: "true", arg2: "false" } }

      it "correctly builds arguments list" do
        expect(subject).to eq("arg2: false")
      end
    end

    context "with default parameters" do
      let(:method) { proc { |arg2: 123| } }
      let(:arguments) { { arg1: "true", arg2: "false" } }

      it "correctly builds arguments list" do
        expect(subject).to eq("arg2: false")
      end
    end

    context "with all parameters" do
      let(:method) { proc { |arg1:, arg2:| } }
      let(:arguments) { { arg1: "true", arg2: "false" } }

      it "correctly builds arguments list" do
        expect(subject).to eq("arg1: true, arg2: false")
      end
    end

    context "with splat" do
      let(:method) { proc { |arg1:, **| } }
      let(:arguments) { { arg1: "true", arg2: "false" } }

      it "correctly builds arguments list" do
        expect(subject).to eq("arg1: true, arg2: false")
      end
    end
  end
end
