# frozen_string_literal: true

RSpec.describe "Rage Multi App" do
  subject { Rage.multi_application.call(env) }

  let(:env) { { "PATH_INFO" => "/" } }
  let(:rails_verifier) { double }
  let(:rage_verifier) { double }

  before do
    stub_const("Rails", double(application: rails_verifier))
    allow(Rage).to receive(:application).and_return(rage_verifier)
  end

  context "with a 200 response" do
    let(:rage_response) { [200, {}, []] }

    it "calls Rage app" do
      expect(rage_verifier).to receive(:call).with(env).and_return(rage_response)
      expect(subject).to eq(rage_response)
    end
  end

  context "with a 404 response" do
    let(:rage_response) { [404, {}, []] }

    it "calls Rage app" do
      expect(rage_verifier).to receive(:call).with(env).and_return(rage_response)
      expect(subject).to eq(rage_response)
    end
  end

  context "with an async response" do
    let(:rage_response) { [:__http_defer__, Fiber.new {}] }

    it "calls Rage app" do
      expect(rage_verifier).to receive(:call).with(env).and_return(rage_response)
      expect(subject).to eq(rage_response)
    end
  end

  context "with an X-Cascade response" do
    let(:rage_response) { [200, { "X-Cascade" => "pass" }, []] }
    let(:rails_response) { :test_rails_response }

    it "calls both Rage and Rails apps" do
      expect(rage_verifier).to receive(:call).with(env).and_return(rage_response)
      expect(rails_verifier).to receive(:call).with(env).and_return(rails_response)
      expect(subject).to eq(rails_response)
    end
  end

  context "with Rails internal request" do
    let(:env) { { "PATH_INFO" => "/rails/action_mailbox" } }
    let(:rage_response) { [200, {}, []] }
    let(:rails_response) { :test_rails_response }

    it "calls both Rage and Rails apps" do
      expect(rage_verifier).to receive(:call).with(env).and_return(rage_response)
      expect(rails_verifier).to receive(:call).with(env).and_return(rails_response)
      expect(subject).to eq(rails_response)
    end
  end
end
