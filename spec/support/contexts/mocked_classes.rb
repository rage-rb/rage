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

  # Build a class backed by a source code file
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

  # @private
  # support circular associations - this holds classes
  # that are not yet known and will be built later
  def self.lazy_classes
    @lazy_classes ||= {}
  end

  # Blueprinter mock - build an ephemeral class object with support for circular references
  def self.let_blueprinter_class(class_name, parent: Blueprinter::Base, &block)
    lazy = lazy_classes
    mocks = mocked_classes

    klass = lazy.delete(class_name) || Class.new(parent)

    klass.define_singleton_method(:name) { class_name }
    klass.define_singleton_method(:const_missing) do |name|
      # defer building the constant in case of a circular reference
      mocks[name.to_s] || (lazy[name.to_s] ||= Class.new(Blueprinter::Base))
    end

    klass.class_eval(block.call)

    # support namespaced serializers
    class_name.split("::").each { |name| mocks[name] = klass }

    before do
      if lazy.any?
        raise NameError, "uninitialized constant #{lazy.keys.first}"
      end

      allow(Object).to receive(:const_get).with(satisfy { |c| c.to_s == class_name.to_s }).and_return(klass)
    end

    klass
  end
end
