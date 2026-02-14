# frozen_string_literal: true

RSpec.describe Rage::JSONFormatter do
  subject { JSON.parse(described_class.new.call(severity, timestamp, nil, message)) }

  let(:severity) { "info" }
  let(:timestamp) { "2020-01-02T12:03:04+00:00" }
  let(:message) { "test message" }

  after do
    Fiber[:__rage_logger_tags] = nil
    Fiber[:__rage_logger_context] = nil
    Fiber[:__rage_logger_final] = nil
  end

  context "with no logger info" do
    it "correctly formats the message" do
      expect(subject).to match({
        "timestamp" => timestamp,
        "pid" => instance_of(String),
        "level" => severity,
        "message" => message
      })
    end
  end

  context "with custom severity" do
    let(:severity) { "warn" }

    it "correctly formats the message" do
      expect(subject).to match({
        "timestamp" => timestamp,
        "pid" => instance_of(String),
        "level" => severity,
        "message" => message
      })
    end
  end

  context "with one tag" do
    before do
      Fiber[:__rage_logger_tags] = ["json-test-tag"]
      Fiber[:__rage_logger_context] = {}
    end

    it "correctly formats the message" do
      expect(subject).to match({
        "timestamp" => timestamp,
        "pid" => instance_of(String),
        "level" => severity,
        "message" => message,
        "tags" => ["json-test-tag"]
      })
    end

    context "with custom context" do
      before do
        Fiber[:__rage_logger_tags] = ["json-test-tag"]
        Fiber[:__rage_logger_context] = { user_id: "test-1", account_id: "test-2" }
      end

      it "correctly formats the message" do
        expect(subject).to match({
          "timestamp" => timestamp,
          "pid" => instance_of(String),
          "level" => severity,
          "message" => message,
          "tags" => ["json-test-tag"],
          "user_id" => "test-1",
          "account_id" => "test-2"
        })
      end
    end
  end

  context "with multiple tags" do
    before do
      Fiber[:__rage_logger_tags] = ["json-test-tag-1", "json-test-tag-2"]
      Fiber[:__rage_logger_context] = {}
    end

    it "correctly formats the message" do
      expect(subject).to match({
        "timestamp" => timestamp,
        "pid" => instance_of(String),
        "level" => severity,
        "message" => message,
        "tags" => ["json-test-tag-1", "json-test-tag-2"]
      })
    end

    context "with custom context" do
      before do
        Fiber[:__rage_logger_tags] = ["json-test-tag-1", "json-test-tag-2"]
        Fiber[:__rage_logger_context] = { user_id: "test-1", account_id: "test-2" }
      end

      it "correctly formats the message" do
        expect(subject).to match({
          "timestamp" => timestamp,
          "pid" => instance_of(String),
          "level" => severity,
          "message" => message,
          "tags" => ["json-test-tag-1", "json-test-tag-2"],
          "user_id" => "test-1",
          "account_id" => "test-2"
        })
      end
    end
  end

  context "with request log" do
    before do
      stub_const("UserProfilesController", double(name: "UserProfilesController"))

      Fiber[:__rage_logger_tags] = ["json-test-tag"]
      Fiber[:__rage_logger_context] = {}
      Fiber[:__rage_logger_final] = {
        env: { "REQUEST_METHOD" => "POST", "PATH_INFO" => "/user_profiles/12345" },
        params: { controller: "user_profiles", action: "create" },
        response: [207, {}, []],
        duration: 1.234
      }
    end

    it "correctly formats the message" do
      expect(subject).to match({
        "timestamp" => timestamp,
        "pid" => instance_of(String),
        "level" => severity,
        "tags" => ["json-test-tag"],
        "controller" => "UserProfilesController",
        "action" => "create",
        "duration" => 1.234,
        "method" => "POST",
        "path" => "/user_profiles/12345",
        "status" => 207
      })
    end

    context "with custom tags" do
      before do
        Fiber[:__rage_logger_tags] << "custom-tag-1" << "custom-tag-2"
      end

      it "correctly formats the message" do
        expect(subject).to match({
          "timestamp" => timestamp,
          "pid" => instance_of(String),
          "level" => severity,
          "tags" => ["json-test-tag", "custom-tag-1", "custom-tag-2"],
          "controller" => "UserProfilesController",
          "action" => "create",
          "duration" => 1.234,
          "method" => "POST",
          "path" => "/user_profiles/12345",
          "status" => 207
        })
      end

      context "with custom context" do
        before do
          Fiber[:__rage_logger_context] = { user_id: "test-1", account_id: "test-2" }
        end

        it "correctly formats the message" do
          expect(subject).to match({
            "timestamp" => timestamp,
            "pid" => instance_of(String),
            "level" => severity,
            "tags" => ["json-test-tag", "custom-tag-1", "custom-tag-2"],
            "controller" => "UserProfilesController",
            "action" => "create",
            "duration" => 1.234,
            "method" => "POST",
            "path" => "/user_profiles/12345",
            "status" => 207,
            "user_id" => "test-1",
            "account_id" => "test-2"
          })
        end
      end
    end

    context "with custom context" do
      before do
        Fiber[:__rage_logger_context] = { user_id: "test-1", account_id: "test-2" }
      end

      it "correctly formats the message" do
        expect(subject).to match({
          "timestamp" => timestamp,
          "pid" => instance_of(String),
          "level" => severity,
          "tags" => ["json-test-tag"],
          "controller" => "UserProfilesController",
          "action" => "create",
          "duration" => 1.234,
          "method" => "POST",
          "path" => "/user_profiles/12345",
          "status" => 207,
          "user_id" => "test-1",
          "account_id" => "test-2"
        })
      end
    end

    context "with no controller/action info" do
      before do
        Fiber[:__rage_logger_tags] = ["json-test-tag"]
        Fiber[:__rage_logger_context] = {}
        Fiber[:__rage_logger_final] = {
          env: { "REQUEST_METHOD" => "POST", "PATH_INFO" => "/user_profiles/12345" },
          params: nil,
          response: [207, {}, []],
          duration: 1.234
        }
      end

      it "correctly formats the message" do
        expect(subject).to match({
          "timestamp" => timestamp,
          "pid" => instance_of(String),
          "level" => severity,
          "tags" => ["json-test-tag"],
          "duration" => 1.234,
          "method" => "POST",
          "path" => "/user_profiles/12345",
          "status" => 207
        })
      end

      context "with custom tags and context" do
        before do
          Fiber[:__rage_logger_tags] << "custom-tag"
          Fiber[:__rage_logger_context] = { user_id: "test-1", account_id: "test-2" }
        end

        it "correctly formats the message" do
          expect(subject).to match({
            "timestamp" => timestamp,
            "pid" => instance_of(String),
            "level" => severity,
            "tags" => ["json-test-tag", "custom-tag"],
            "duration" => 1.234,
            "method" => "POST",
            "path" => "/user_profiles/12345",
            "status" => 207,
            "user_id" => "test-1",
            "account_id" => "test-2"
          })
        end
      end
    end
  end
end
