# frozen_string_literal: true

# @private
class Rage::Internal
  class << self
    # Define a method based on a block.
    # @param klass [Class] the class to define the method in
    # @param block [Proc] the implementation of the new method
    # @return [Symbol] the name of the newly defined method
    def define_dynamic_method(klass, block)
      name = dynamic_name_seed.next.join
      klass.define_method("__rage_dynamic_#{name}", block)
    end

    # Define a method that will call a specified method if a condition is `true` or yield if `false`.
    # @param klass [Class] the class to define the method in
    # @param method_name [Symbol] the method to call if the condition is `true`
    # @return [Symbol] the name of the newly defined method
    def define_maybe_yield(klass, method_name)
      name = dynamic_name_seed.next.join

      klass.class_eval <<~RUBY, __FILE__, __LINE__ + 1
        def __rage_dynamic_#{name}(condition)
          if condition
            #{method_name} { yield }
          else
            yield
          end
        end
      RUBY
    end

    # Build a string representation of keyword arguments based on the parameters expected by the method.
    # @param method [Method, Proc] the method to build arguments for
    # @param arguments [Hash] the arguments to include in the string representation
    # @return [String] the string representation of the method arguments
    def build_arguments(method, arguments)
      expected_parameters = method.parameters

      arguments.filter_map { |arg_name, arg_value|
        if expected_parameters.any? { |param_type, param_name| param_name == arg_name || param_type == :keyrest }
          "#{arg_name}: #{arg_value}"
        end
      }.join(", ")
    end

    # Extract the host from a host:port authority while leaving bare IPv6 literals unchanged.
    # @param authority [String, nil]
    # @return [String, nil]
    def extract_host(authority)
      if authority&.start_with?("[")
        authority.sub(/\]:\d+\z/, "]")
      elsif authority&.count(":") == 1
        authority.sub(/:\d+\z/, "")
      else
        authority
      end
    end

    # Generate a stream name based on the provided object.
    # @param streamables [#id, String, Symbol, Numeric, Array] an object that will be used to generate the stream name
    # @return [String] the generated stream name
    # @raise [ArgumentError] if the provided object cannot be used to generate a stream name
    def stream_name_for(streamables)
      return streamables if streamables.is_a?(String)

      name_segments = Array(streamables).map do |streamable|
        if streamable.respond_to?(:id)
          "#{streamable.class.name}:#{streamable.id}"
        elsif streamable.is_a?(String) || streamable.is_a?(Symbol) || streamable.is_a?(Numeric)
          streamable
        else
          raise ArgumentError, "Unable to generate stream name. Expected an object that responds to `id`, got: #{streamable.class}"
        end
      end

      name_segments.join(":")
    end

    LOCK_FILE_SUFFIX = rand(0x100000000).to_s(36)

    # Pick a worker process to execute a block of code.
    # This is useful for ensuring that certain code is only executed by a single worker in a multi-worker setup, e.g. for broadcasting messages to known streams or for running periodic tasks.
    # @yield The block of code to be executed by the picked worker
    def pick_a_worker(purpose:, &block)
      attempt = proc do
        lock_path = Pathname.new(Dir.tmpdir).join("rage-#{purpose}-lock-#{LOCK_FILE_SUFFIX}")

        lock_file = File.open(lock_path, File::CREAT | File::WRONLY)

        if lock_file.flock(File::LOCK_EX | File::LOCK_NB)
          Iodine.on_state(:on_finish) { File.unlink(lock_file) if File.exist?(lock_file) }
          worker_locks << lock_file
          block.call
        end
      end

      Iodine.running? ? attempt.call : Iodine.on_state(:on_start) { attempt.call }
    end

    private

    def worker_locks
      @worker_locks ||= []
    end

    def dynamic_name_seed
      @dynamic_name_seed ||= ("a".."j").to_a.permutation
    end
  end
end
