# frozen_string_literal: true

RSpec.describe Rage::Cable do
  describe ".application" do
    context "with invalid namespace" do
      it "raises ArgumentError when namespace is not a Module" do
        expect {
          described_class.application(namespace: "not_a_module")
        }.to raise_error(ArgumentError, "The `namespace` option must be a Module, got String.")
      end

      it "raises ArgumentError when namespace is an integer" do
        expect {
          described_class.application(namespace: 123)
        }.to raise_error(ArgumentError, "The `namespace` option must be a Module, got Integer.")
      end
    end
  end

  describe ".__protocol_for" do
    it "returns ActioncableV1Json for :actioncable_v1_json symbol" do
      expect(described_class.__protocol_for(:actioncable_v1_json)).to eq(Rage::Cable::Protocols::ActioncableV1Json)
    end

    it "returns RawWebSocketJson for :raw_websocket_json symbol" do
      expect(described_class.__protocol_for(:raw_websocket_json)).to eq(Rage::Cable::Protocols::RawWebSocketJson)
    end

    it "returns the class directly when a Class is passed" do
      expect(described_class.__protocol_for(Rage::Cable::Protocols::ActioncableV1Json)).to eq(Rage::Cable::Protocols::ActioncableV1Json)
    end

    it "raises ArgumentError for unknown protocol" do
      expect {
        described_class.__protocol_for(:unknown_protocol)
      }.to raise_error(ArgumentError, "Unknown protocol. Supported values are `:actioncable_v1_json` and `:raw_websocket_json`.")
    end

    it "raises ArgumentError for nil protocol" do
      expect {
        described_class.__protocol_for(nil)
      }.to raise_error(ArgumentError, "Unknown protocol. Supported values are `:actioncable_v1_json` and `:raw_websocket_json`.")
    end
  end

  describe ".__rage_app_name" do
    let(:protocol) { double(protocol_definition: {}, init: nil) }

    before do
      allow(Rage.config.cable).to receive(:protocol).and_return(:actioncable_v1_json)
      allow(Rage.config.cable).to receive(:middlewares).and_return([])
      allow(Rage::Cable::Protocols::ActioncableV1Json).to receive(:init)
      described_class.__protocols.clear
    end

    after do
      described_class.__protocols.clear
    end

    it "returns 'Rage::Cable' when namespace is Object" do
      app = described_class.application(namespace: Object)
      root_app = app.__rage_root_app

      expect(root_app.__rage_app_name).to eq("Rage::Cable")
    end

    it "returns namespaced name when namespace is custom module" do
      custom_namespace = Module.new
      stub_const("MyCustomCable", custom_namespace)

      app = described_class.application(namespace: MyCustomCable)
      root_app = app.__rage_root_app

      expect(root_app.__rage_app_name).to eq("Rage::Cable(namespace: MyCustomCable)")
    end
  end

  describe Rage::Cable::Relay do
    let(:protocol1) { double("Protocol1") }
    let(:protocol2) { double("Protocol2") }

    describe ".broadcast" do
      it "broadcasts to all registered protocols" do
        allow(Rage::Cable).to receive(:__protocols).and_return([protocol1, protocol2])

        expect(protocol1).to receive(:broadcast).with("test_stream", { message: "hello" })
        expect(protocol2).to receive(:broadcast).with("test_stream", { message: "hello" })

        described_class.broadcast("test_stream", { message: "hello" })
      end

      it "does nothing when no protocols are registered" do
        allow(Rage::Cable).to receive(:__protocols).and_return([])
        expect { described_class.broadcast("test_stream", { data: 1 }) }.not_to raise_error
      end
    end
  end
end
