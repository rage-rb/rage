require "rage/sync_fiber"

RSpec.describe Fiber do
  describe ".schedule" do
    let(:fiber_instance) { instance_double(Fiber) }

    it "runs immediately" do
      expect(Fiber).to receive(:new).with(blocking: true).and_return(fiber_instance)
      expect(fiber_instance).to receive(:resume).and_return(true)
      expect(described_class.schedule { rand }).to eq(fiber_instance)
    end
  end

  describe ".await" do
    let(:fiber_instance) { instance_double(Fiber, __get_result: 10) }

    it "immediately returns result" do
      expect(described_class.await([fiber_instance])).to eq([10])
    end
  end
end
