# frozen_string_literal: true

require "stringio"

RSpec.describe Rage::Logger do
  subject { described_class.new(io) }

  let(:io) { StringIO.new }

  before do
    Thread.current[:rage_logger] = {
      tags: ["my_test_tag"],
      context: {},
      request_start: 123
    }

    allow(Fiber).to receive(:scheduler).and_return(true)
    allow(Iodine::Rack::Utils).to receive(:gen_timestamp).and_return("very_accurate_timestamp")
    allow(Process).to receive(:pid).and_return(777)
  end

  it "adds an info entry" do
    subject.info "test message"
    expect(io.tap(&:rewind).read).to eq("[my_test_tag] timestamp=very_accurate_timestamp pid=777 level=info message=test message\n")
  end

  it "adds an fatal entry" do
    subject.fatal "test message"
    expect(io.tap(&:rewind).read).to eq("[my_test_tag] timestamp=very_accurate_timestamp pid=777 level=fatal message=test message\n")
  end

  it "adds a debug entry" do
    subject.debug "test message"
    expect(io.tap(&:rewind).read).to eq("[my_test_tag] timestamp=very_accurate_timestamp pid=777 level=debug message=test message\n")
  end

  it "works with a block" do
    subject.error { "test message" }
    expect(io.tap(&:rewind).read).to eq("[my_test_tag] timestamp=very_accurate_timestamp pid=777 level=error message=test message\n")
  end

  context "with a custom level" do
    before do
      subject.level = Logger::WARN
    end

    it "ignores a debug call" do
      subject.debug "test message"
      expect(io.tap(&:rewind).read).to be_empty
    end

    it "ignores an info call" do
      subject.info "test message"
      expect(io.tap(&:rewind).read).to be_empty
    end

    it "ignores an info call with a block" do
      subject.info { raise }
      expect(io.tap(&:rewind).read).to be_empty
    end

    it "adds a warn entry" do
      subject.warn "test message"
      expect(io.tap(&:rewind).read).to eq("[my_test_tag] timestamp=very_accurate_timestamp pid=777 level=warn message=test message\n")
    end
  end

  context "with a custom formatter" do
    before do
      subject.formatter = ->(severity, time, _, message) do
        "[#{severity}] + #{time.monday? && time.tuesday?} + #{message}"
      end
    end

    it "uses a custom formatter" do
      subject.error "custom message"
      expect(io.tap(&:rewind).read).to eq("[3] + false + custom message")
    end
  end

  context "with tags" do
    it "adds a tag to an entry" do
      subject.tagged("rspec") do
        subject.info "test passed"
      end

      expect(io.tap(&:rewind).read).to eq("[my_test_tag][rspec] timestamp=very_accurate_timestamp pid=777 level=info message=test passed\n")
    end

    it "works correctly with multiple nesting levels" do
      subject.tagged("rspec") do
        subject.tagged("inner_tag") do
          subject.fatal "hello there"
        end

        subject.debug "debug message"
      end

      io.rewind
      expect(io.readline).to eq("[my_test_tag][rspec][inner_tag] timestamp=very_accurate_timestamp pid=777 level=fatal message=hello there\n")
      expect(io.readline).to eq("[my_test_tag][rspec] timestamp=very_accurate_timestamp pid=777 level=debug message=debug message\n")
    end
  end

  context "with context" do
    it "adds a key to an entry" do
      subject.with_context(test_id: "1133") do
        subject.info "passed"
      end

      expect(io.tap(&:rewind).read).to eq("[my_test_tag] timestamp=very_accurate_timestamp pid=777 level=info test_id=1133 message=passed\n")
    end

    it "works correctly with multiple nesting levels" do
      subject.tagged("rspec") do
        subject.with_context(a: 111) do
          subject.debug "debug message"
        end

        subject.with_context(b: 222) do
          subject.tagged("test_tag") do
            subject.info "info message"

            subject.with_context(c: "333", d: "444") do
              subject.unknown "unknown message"
            end
          end

          subject.warn "warn message"
        end
      end

      io.rewind
      expect(io.readline).to eq("[my_test_tag][rspec] timestamp=very_accurate_timestamp pid=777 level=debug a=111 message=debug message\n")
      expect(io.readline).to eq("[my_test_tag][rspec][test_tag] timestamp=very_accurate_timestamp pid=777 level=info b=222 message=info message\n")
      expect(io.readline).to eq("[my_test_tag][rspec][test_tag] timestamp=very_accurate_timestamp pid=777 level=unknown b=222 c=333 d=444 message=unknown message\n")
      expect(io.readline).to eq("[my_test_tag][rspec] timestamp=very_accurate_timestamp pid=777 level=warn b=222 message=warn message\n")
    end
  end

  context "from outside the application" do
    before do
      stub_const("IRB", Class.new)
    end

    it "correctly adds an entry" do
      subject.info "this is a test message"
      expect(io.tap(&:rewind).read).to eq("this is a test message\n")
    end

    it "correctly adds a block entry" do
      subject.info { "this is a test message" }
      expect(io.tap(&:rewind).read).to eq("this is a test message\n")
    end

    it "ignores tags" do
      subject.tagged("rspec") do
        subject.info "this is a test message"
      end
      expect(io.tap(&:rewind).read).to eq("this is a test message\n")
    end

    it "ignores context" do
      subject.with_context(a: "1") do
        subject.info "this is a test message"
      end
      expect(io.tap(&:rewind).read).to eq("this is a test message\n")
    end
  end

  context "with request logs" do
    before do
      Thread.current[:rage_logger][:final] = {
        env: { "REQUEST_METHOD" => "GET", "PATH_INFO" => "/test_path" },
        params: { controller: "rspec", action: "index", id: "123" },
        response: [300, {}, []],
        duration: 1.45
      }
    end

    it "correctly add an entry" do
      subject.info ""
      expect(io.tap(&:rewind).read).to eq("[my_test_tag] timestamp=very_accurate_timestamp pid=777 level=info method=GET path=/test_path controller=rspec action=index status=300 duration=1.45\n")
    end

    context "without params" do
      before do
        Thread.current[:rage_logger][:final].delete(:params)
      end

      it "correctly add an entry" do
        subject.info ""
        expect(io.tap(&:rewind).read).to eq("[my_test_tag] timestamp=very_accurate_timestamp pid=777 level=info method=GET path=/test_path status=300 duration=1.45\n")
      end
    end
  end

  context "with nil destination" do
    let(:io) { nil }

    it "doesn't add a string entry" do
      expect(
        subject.fatal "this is a test message"
      ).to be(false)
    end

    it "doesn't add a block entry" do
      expect {
        subject.fatal { raise }
      }.not_to raise_error
    end
  end

  context "with LogDevice options" do
    subject { described_class.new(io, shift_age: "weekly", shift_size: 3456, shift_period_suffix: "%d-%d", binmode: true) }

    it "passes options down" do
      expect { subject }.not_to raise_error
    end
  end
end
