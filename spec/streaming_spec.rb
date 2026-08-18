# frozen_string_literal: true

RSpec.describe Rage::Streaming do
  before :all do
    Fiber.set_scheduler(Rage::FiberScheduler.new)
  end

  after :all do
    Fiber.set_scheduler(nil)
  end

  class FakeRackStream
    attr_reader :chunks, :close_count

    def initialize(script: [])
      @script = script
      @chunks = []
      @close_count = 0
      @channel = "test:stream:wake:#{object_id}"
    end

    def write(data)
      result = @script.empty? ? :ok : @script.shift
      @chunks << data if result == :ok
      result
    end

    def close
      @close_count += 1
      nil
    end

    def closed?
      @close_count > 0
    end

    def wake_channel
      @channel
    end
  end

  def wait_until(timeout = 2)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    until yield
      raise "timed out waiting for condition" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep(0.02)
    end
  end

  it "rejects a source that doesn't respond to #each" do
    expect { described_class.new(proc {}) }.to raise_error(ArgumentError, /must respond to #each/)
  end

  it "writes every chunk and closes the stream" do
    stream = FakeRackStream.new
    streaming = described_class.new(%w[a b c].each)

    within_reactor do
      streaming.call(stream)
      wait_until { stream.close_count > 0 }

      -> do
        expect(stream.chunks).to eq(%w[a b c])
        expect(stream.close_count).to eq(1)
      end
    end
  end

  it "coerces chunks to strings and skips nils" do
    stream = FakeRackStream.new
    streaming = described_class.new([1, nil, :chunk].each)

    within_reactor do
      streaming.call(stream)
      wait_until { stream.close_count > 0 }

      -> { expect(stream.chunks).to eq(%w[1 chunk]) }
    end
  end

  it "stops producing once the client disconnects" do
    stream = FakeRackStream.new(script: [:ok, :disconnected])
    streaming = described_class.new(%w[a b c].each)

    within_reactor do
      streaming.call(stream)
      wait_until { stream.close_count > 0 }

      -> do
        expect(stream.chunks).to eq(%w[a])
        expect(stream.close_count).to eq(1)
      end
    end
  end

  it "stops producing and logs on a write error" do
    logger = double("logger")
    allow(Rage).to receive(:logger).and_return(logger)
    allow(logger).to receive(:error)

    stream = FakeRackStream.new(script: [:error])
    streaming = described_class.new(%w[a b c].each)

    within_reactor do
      streaming.call(stream)
      wait_until { stream.close_count > 0 }

      -> do
        expect(stream.chunks).to be_empty
        expect(stream.close_count).to eq(1)
        expect(logger).to have_received(:error).with(/stream\.write returned :error/)
      end
    end
  end

  it "parks the producer on :would_block and resumes it on a drain message" do
    stream = FakeRackStream.new(script: [:ok, :would_block, :ok, :would_block])
    streaming = described_class.new(%w[a b c].each)

    within_reactor do
      streaming.call(stream)
      expect(stream.close_count).to eq(0) # parked, not finished

      Iodine.publish(stream.wake_channel, "drain", Iodine::PubSub::PROCESS)
      wait_until { stream.chunks == %w[a b] }

      Iodine.publish(stream.wake_channel, "drain", Iodine::PubSub::PROCESS)
      wait_until { stream.close_count > 0 }

      -> do
        expect(stream.chunks).to eq(%w[a b c])
        expect(stream.close_count).to eq(1)
      end
    end
  end

  it "wakes a parked producer when the stream is closed externally" do
    stream = FakeRackStream.new(script: [:would_block, :closed])
    streaming = described_class.new(%w[a b c].each)

    within_reactor do
      streaming.call(stream)
      expect(stream.close_count).to eq(0) # parked, not finished

      Iodine.publish(stream.wake_channel, "close", Iodine::PubSub::PROCESS)
      wait_until { stream.close_count > 0 }

      -> do
        expect(stream.chunks).to be_empty
        expect(stream.close_count).to eq(1)
      end
    end
  end

  it "slices chunks larger than the max write size" do
    stream = FakeRackStream.new
    data = "x" * (2 * 256 * 1024 + 100)
    streaming = described_class.new([data].each)

    within_reactor do
      streaming.call(stream)
      wait_until { stream.close_count > 0 }

      -> do
        expect(stream.chunks.map(&:bytesize)).to eq([256 * 1024, 256 * 1024, 100])
        expect(stream.chunks.join).to eq(data)
      end
    end
  end

  it "doesn't slice chunks at or below the max write size" do
    stream = FakeRackStream.new
    data = "x" * (256 * 1024)
    streaming = described_class.new([data].each)

    within_reactor do
      streaming.call(stream)
      wait_until { stream.close_count > 0 }

      -> { expect(stream.chunks.map(&:bytesize)).to eq([256 * 1024]) }
    end
  end

  it "stops mid-chunk when the stream closes between slices" do
    stream = FakeRackStream.new(script: [:ok, :closed])
    data = "x" * (2 * 256 * 1024)
    streaming = described_class.new([data].each)

    within_reactor do
      streaming.call(stream)
      wait_until { stream.close_count > 0 }

      -> do
        expect(stream.chunks.map(&:bytesize)).to eq([256 * 1024])
        expect(stream.close_count).to eq(1)
      end
    end
  end

  it "parks between slices on :would_block and resumes on a drain message" do
    stream = FakeRackStream.new(script: [:ok, :would_block])
    data = "x" * (2 * 256 * 1024)
    streaming = described_class.new([data].each)

    within_reactor do
      streaming.call(stream)
      expect(stream.close_count).to eq(0) # parked mid-chunk, not finished

      Iodine.publish(stream.wake_channel, "drain", Iodine::PubSub::PROCESS)
      wait_until { stream.close_count > 0 }

      -> do
        expect(stream.chunks.map(&:bytesize)).to eq([256 * 1024, 256 * 1024])
        expect(stream.chunks.join).to eq(data)
      end
    end
  end

  it "closes the stream when the source raises" do
    logger = double("logger")
    allow(Rage).to receive(:logger).and_return(logger)
    allow(logger).to receive(:error)
    allow(Rage::Errors).to receive(:report)

    stream = FakeRackStream.new
    source = Enumerator.new do |y|
      y << "a"
      raise "boom"
    end
    streaming = described_class.new(source)

    within_reactor do
      streaming.call(stream)
      wait_until { stream.close_count > 0 }

      -> do
        expect(stream.chunks).to eq(%w[a])
        expect(stream.close_count).to eq(1)
        expect(Rage::Errors).to have_received(:report).with(instance_of(RuntimeError))
      end
    end
  end

  it "unsubscribes from the wake channel once the stream completes" do
    stream = FakeRackStream.new
    streaming = described_class.new(%w[a].each)

    within_reactor do
      streaming.call(stream)
      wait_until { stream.close_count > 0 && !Iodine.subscribed?(stream.wake_channel) }

      -> { expect(Iodine.subscribed?(stream.wake_channel)).to be(false) }
    end
  end
end
