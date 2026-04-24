# frozen_string_literal: true

module Rage::Errors
  @reporters = []

  class << self
    # Register a new error reporter.
    # A reporter should respond to `#call` and accept one of:
    # - `call(exception)`
    # - `call(exception, context: {})`
    #
    # @param reporter [#call]
    # @return [self]
    def <<(reporter)
      raise ArgumentError, "reporter must respond to #call" unless reporter.respond_to?(:call)

      index = @reporters.length
      @reporters << reporter

      arguments = Rage::Internal.build_arguments(
        reporter.method(:call),
        { context: "context" }
      )
      call_arguments = arguments.empty? ? "" : ", #{arguments}"

      singleton_class.class_eval <<~RUBY, __FILE__, __LINE__ + 1
        def __report_#{index}(exception, context)
          @reporters[#{index}].call(exception#{call_arguments})
        end
      RUBY

      self
    end

    # Forward an exception to all registered reporters.
    #
    # @param exception [Exception]
    # @param context [Hash]
    # @return [nil]
    def report(exception, context: {})
      return if @reporters.empty?
      return if exception.instance_variable_defined?(:@_rage_error_reported)

      ensure_backtrace(exception)

      @reporters.length.times do |i|
        __send__(:"__report_#{i}", exception, context)
      rescue => e
        Rage.logger.error("Error reporter #{@reporters[i].class} failed: #{e.class} (#{e.message})")
      end

      exception.instance_variable_set(:@_rage_error_reported, true) unless exception.frozen?

      nil
    end

    private

    def ensure_backtrace(exception)
      return if exception.frozen?
      return unless exception.backtrace.nil?

      begin
        raise exception
      rescue exception.class
      end
    end
  end

  class BadRequest < StandardError
  end

  class RouterError < StandardError
  end

  class UnknownHTTPMethod < StandardError
  end

  class InvalidCustomProxy < StandardError
  end

  class AmbiguousRenderError < StandardError
  end
end
