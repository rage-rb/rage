# frozen_string_literal: true

module Rage::Errors
  ReporterEntry = Struct.new(:reporter, :method_name)
  private_constant :ReporterEntry

  @reporters = []
  @next_reporter_id = 0

  class << self
    # Forward an exception to all registered reporters.
    #
    # @param exception [Exception]
    # @param context [Hash]
    # @return [nil]
    def report(exception, context: {})
      return if @reporters.empty?
      return if exception.instance_variable_defined?(:@_rage_error_reported)

      ensure_backtrace(exception)

      @reporters.each do |entry|
        __send__(entry.method_name, entry.reporter, exception, context)
      rescue => e
        Rage.logger.error("Error reporter #{entry.reporter.class} failed while reporting #{exception.class}: #{e.class} (#{e.message})")
      end

      exception.instance_variable_set(:@_rage_error_reported, true) unless exception.frozen?

      nil
    end

    # @private
    def __register_reporter(reporter)
      raise ArgumentError, "error handler must respond to #call" unless reporter.respond_to?(:call)

      reporter_id = @next_reporter_id
      @next_reporter_id += 1
      method_name = :"__report_#{reporter_id}"

      arguments = Rage::Internal.build_arguments(
        reporter.method(:call),
        { context: "context" }
      )
      call_arguments = arguments.empty? ? "" : ", #{arguments}"

      singleton_class.class_eval <<~RUBY, __FILE__, __LINE__ + 1
        def #{method_name}(reporter, exception, context)
          reporter.call(exception#{call_arguments})
        end
      RUBY

      @reporters << ReporterEntry.new(reporter, method_name)

      self
    end

    # @private
    def __unregister_reporter(reporter)
      @reporters.delete_if do |entry|
        next false unless entry.reporter == reporter

        singleton_class.remove_method(entry.method_name) if singleton_class.method_defined?(entry.method_name)
        true
      end

      self
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

    private :__register_reporter, :__unregister_reporter
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
