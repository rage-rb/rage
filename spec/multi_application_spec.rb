# frozen_string_literal: true

RSpec.describe "Rage Multi App" do
  subject { Rage.multi_application.call(env) }

  let(:env) { { "PATH_INFO"=> "/" } }
  let(:rails_verifier) { double }
  let(:rage_verifier) { double }

  before do
    stub_const("Rails", double(application: rails_verifier))
    allow(Rage).to receive(:application).and_return(rage_verifier)
  end

  context "with a 200 response" do
    it "calls Rage app" do
      expect(rage_verifier).to receive(:call).with(env).and_return([200, {}, []])
      subject
    end
  end

  context "with a 404 response" do
    it "calls Rage app" do
      expect(rage_verifier).to receive(:call).with(env).and_return([404, {}, []])
      subject
    end
  end

  context "with an async response" do
    it "calls Rage app" do
      expect(rage_verifier).to receive(:call).with(env).and_return([:__http_defer__, Fiber.new {}])
      subject
    end
  end

  context "with an X-Cascade response" do
    it "calls both Rage and Rails apps" do
      expect(rage_verifier).to receive(:call).with(env).and_return([200, { "X-Cascade" => "pass" }, []])
      expect(rails_verifier).to receive(:call).with(env)
      subject
    end
  end

  context "with Rails internal request" do
    let(:env) { { "PATH_INFO"=> "/rails/action_mailbox" } }

    it "calls both Rage and Rails apps" do
      expect(rage_verifier).to receive(:call).with(env).and_return([200, {}, []])
      expect(rails_verifier).to receive(:call).with(env)
      subject
    end
  end
end
