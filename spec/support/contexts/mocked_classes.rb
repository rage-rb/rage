# frozen_string_literal: true

require "ostruct"

RSpec.shared_context "mocked_classes" do
  before do
    allow(Object).to receive(:const_get).and_call_original
    allow(Object).to receive(:const_source_location).and_call_original
  end

  def self.mocked_classes
    @mocked_classes ||= OpenStruct.new
  end

  def self.let_class(class_name, parent: Object, &block)
    source = Tempfile.new.tap do |f|
      if block
        f.write <<~RUBY
          class #{class_name} #{"< #{parent.name}" if parent != Object}
            #{block.call}
          end
        RUBY
      end
      f.close
    end

    klass = Class.new(parent, &block)
    klass.define_singleton_method(:name) { class_name }

    mocked_classes[class_name] = klass

    before do
      allow(Object).to receive(:const_get).with(satisfy { |c| c.to_s == class_name.to_s }).and_return(klass)
      allow(Object).to receive(:const_source_location).with(class_name).and_return(source.path)
    end
  end
end
