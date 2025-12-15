# frozen_string_literal: true

RSpec.describe Rage::Telemetry::Handler do
  describe ".handle" do
    subject { handler.handlers_map }

    before do
      allow(Rage::Telemetry).to receive(:__registry).and_return({
        "core.fiber.spawn" => double,
        "core.fiber.await" => double,
        "core.fiber.dispatch" => double,
        "deferred.task.enqueue" => double,
        "deferred.task.process" => double,
        "cable.action.process" => double,
        "cable.connection.process" => double,
        "controller.action.process" => double,
        "events.event.publish" => double,
        "events.subscriber.process" => double
      })
    end

    context "with one span" do
      let(:handler) do
        Class.new(Rage::Telemetry::Handler) do
          handle "controller.action.process", with: :test
        end
      end

      it "correctly registers handlers" do
        expect(subject).to match({ "controller.action.process" => [:test] })
      end
    end

    context "with multiple spans" do
      let(:handler) do
        Class.new(Rage::Telemetry::Handler) do
          handle "controller.action.process", "cable.action.process", with: :test
        end
      end

      it "correctly registers handlers" do
        expect(subject).to match({
          "controller.action.process" => [:test],
          "cable.action.process" => [:test]
        })
      end
    end

    context "with multiple handlers" do
      let(:handler) do
        Class.new(Rage::Telemetry::Handler) do
          handle "controller.action.process", "cable.action.process", with: :test_1
          handle "controller.action.process", with: :test_2
          handle "core.fiber.spawn", with: :test_3
        end
      end

      it "correctly registers handlers" do
        expect(subject).to match({
          "controller.action.process" => [:test_1, :test_2],
          "cable.action.process" => [:test_1],
          "core.fiber.spawn" => [:test_3]
        })
      end
    end

    context "with wildcard spans" do
      let(:handler) do
        Class.new(Rage::Telemetry::Handler) do
          handle "cable.*", with: :test
        end
      end

      it "correctly registers handlers" do
        expect(subject).to match({
          "cable.connection.process" => [:test],
          "cable.action.process" => [:test]
        })
      end
    end

    context "with wildcard spans" do
      let(:handler) do
        Class.new(Rage::Telemetry::Handler) do
          handle "cable.*", with: :test
        end
      end

      it "correctly registers handlers" do
        expect(subject).to match({
          "cable.connection.process" => [:test],
          "cable.action.process" => [:test]
        })
      end
    end

    context "with wildcard and regular spans" do
      let(:handler) do
        Class.new(Rage::Telemetry::Handler) do
          handle "*.process", "core.fiber.spawn", with: :test
        end
      end

      it "correctly registers handlers" do
        expect(subject).to match({
          "controller.action.process" => [:test],
          "cable.connection.process" => [:test],
          "cable.action.process" => [:test],
          "deferred.task.process" => [:test],
          "events.subscriber.process" => [:test],
          "core.fiber.spawn" => [:test]
        })
      end
    end

    context "with all spans" do
      let(:handler) do
        Class.new(Rage::Telemetry::Handler) do
          handle "*", with: :test
        end
      end

      it "correctly registers handlers" do
        expect(subject).to match({
          "core.fiber.spawn" => [:test],
          "core.fiber.await" => [:test],
          "core.fiber.dispatch" => [:test],
          "deferred.task.enqueue" => [:test],
          "deferred.task.process" => [:test],
          "cable.action.process" => [:test],
          "cable.connection.process" => [:test],
          "controller.action.process" => [:test],
          "events.event.publish" => [:test],
          "events.subscriber.process" => [:test]
        })
      end
    end

    context "with one span and except" do
      let(:handler) do
        Class.new(Rage::Telemetry::Handler) do
          handle "controller.action.process", except: "controller.action.process", with: :test
        end
      end

      it "correctly registers handlers" do
        expect(subject).to be_empty
      end
    end

    context "with multiple spans and except" do
      let(:handler) do
        Class.new(Rage::Telemetry::Handler) do
          handle "controller.action.process", "cable.action.process",
            except: "controller.action.process",
            with: :test
        end
      end

      it "correctly registers handlers" do
        expect(subject).to match({
          "cable.action.process" => [:test]
        })
      end
    end

    context "with wildcard spans and except" do
      let(:handler) do
        Class.new(Rage::Telemetry::Handler) do
          handle "core.fiber.*",
            except: "core.fiber.await",
            with: :test
        end
      end

      it "correctly registers handlers" do
        expect(subject).to match({
          "core.fiber.dispatch" => [:test],
          "core.fiber.spawn" => [:test]
        })
      end
    end

    context "with wildcard except" do
      let(:handler) do
        Class.new(Rage::Telemetry::Handler) do
          handle "*.process",
            except: "cable.*",
            with: :test
        end
      end

      it "correctly registers handlers" do
        expect(subject).to match({
          "controller.action.process" => [:test],
          "deferred.task.process" => [:test],
          "events.subscriber.process" => [:test]
        })
      end
    end

    context "with array except" do
      let(:handler) do
        Class.new(Rage::Telemetry::Handler) do
          handle "*.process",
            except: ["cable.*", "controller.action.process"],
            with: :test
        end
      end

      it "correctly registers handlers" do
        expect(subject).to match({
          "deferred.task.process" => [:test],
          "events.subscriber.process" => [:test]
        })
      end
    end

    context "with all spans and except" do
      let(:handler) do
        Class.new(Rage::Telemetry::Handler) do
          handle "*",
            except: "*.process",
            with: :test
        end
      end

      it "correctly registers handlers" do
        expect(subject).to match({
          "core.fiber.spawn" => [:test],
          "core.fiber.await" => [:test],
          "core.fiber.dispatch" => [:test],
          "deferred.task.enqueue" => [:test],
          "events.event.publish" => [:test]
        })
      end
    end

    context "with duplicate spans" do
      let(:handler) do
        Class.new(Rage::Telemetry::Handler) do
          handle "events.*", "events.event.publish", with: :test
        end
      end

      it "correctly registers handlers" do
        expect(subject).to match({
          "events.event.publish" => [:test],
          "events.subscriber.process" => [:test]
        })
      end
    end

    context "with invalid span" do
      it "raises an exception" do
        expect {
          Class.new(Rage::Telemetry::Handler) do
            handle "invalid.span", with: :test
          end
        }.to raise_error(/Unknown span ID/)
      end
    end

    context "with multiple spans with invalid span" do
      it "raises an exception" do
        expect {
          Class.new(Rage::Telemetry::Handler) do
            handle "controller.action.process", "invalid.span", with: :test
          end
        }.to raise_error(/Unknown span ID/)
      end
    end

    context "with invalid wildcard span" do
      it "raises an exception" do
        expect {
          Class.new(Rage::Telemetry::Handler) do
            handle "test.*", with: :test
          end
        }.to raise_error(/No spans match/)
      end
    end

    context "with invalid except span" do
      it "raises an exception" do
        expect {
          Class.new(Rage::Telemetry::Handler) do
            handle "cable.*", except: "invalid.span", with: :test
          end
        }.to raise_error(/Unknown span ID/)
      end
    end

    context "with invalid wildcard except span" do
      it "raises an exception" do
        expect {
          Class.new(Rage::Telemetry::Handler) do
            handle "cable.*", except: "invalid.*", with: :test
          end
        }.to raise_error(/No spans match/)
      end
    end
  end
end
