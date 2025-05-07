class Rage::Cable::Channel
  # @private
  INTERNAL_ACTIONS = [:subscribed, :unsubscribed]

  class << self
    # @private
    attr_reader :__prepared_actions

    # @private
    attr_reader :__channels

    # @private
    # returns a list of actions that can be called remotely
    def __register_actions
      actions = (
        public_instance_methods(true) - Rage::Cable::Channel.public_instance_methods(true)
      ).reject { |m| m.start_with?("__rage_tmp") || m.start_with?("__run") }

      @__prepared_actions = (INTERNAL_ACTIONS + actions).each_with_object({}) do |action_name, memo|
        memo[action_name] = __register_action_proc(action_name)
      end

      actions - INTERNAL_ACTIONS
    end

    # @private
    # rubocop:disable Layout/HeredocIndentation, Layout/IndentationWidth, Layout/EndAlignment, Layout/ElseAlignment
    def __register_action_proc(action_name)
      if action_name == :subscribed && @__hooks
        before_subscribe_chunk = if @__hooks[:before_subscribe]
          lines = @__hooks[:before_subscribe].map do |h|
            condition = if h[:if] && h[:unless]
              "if #{h[:if]} && !#{h[:unless]}"
            elsif h[:if]
              "if #{h[:if]}"
            elsif h[:unless]
              "unless #{h[:unless]}"
            end

            <<~RUBY
              #{h[:name]} #{condition}
              return if @__subscription_rejected
            RUBY
          end

          lines.join("\n")
        end

        after_subscribe_chunk = if @__hooks[:after_subscribe]
          lines = @__hooks[:after_subscribe].map do |h|
            condition = if h[:if] && h[:unless]
              "if #{h[:if]} && !#{h[:unless]}"
            elsif h[:if]
              "if #{h[:if]}"
            elsif h[:unless]
              "unless #{h[:unless]}"
            end

            <<~RUBY
              #{h[:name]} #{condition}
            RUBY
          end

          lines.join("\n")
        end
      end

      if action_name == :unsubscribed && @__hooks
        before_unsubscribe_chunk = if @__hooks[:before_unsubscribe]
          lines = @__hooks[:before_unsubscribe].map do |h|
            condition = if h[:if] && h[:unless]
              "if #{h[:if]} && !#{h[:unless]}"
            elsif h[:if]
              "if #{h[:if]}"
            elsif h[:unless]
              "unless #{h[:unless]}"
            end

            <<~RUBY
              #{h[:name]} #{condition}
            RUBY
          end

          lines.join("\n")
        end

        after_unsubscribe_chunk = if @__hooks[:after_unsubscribe]
          lines = @__hooks[:after_unsubscribe].map do |h|
            condition = if h[:if] && h[:unless]
              "if #{h[:if]} && !#{h[:unless]}"
            elsif h[:if]
              "if #{h[:if]}"
            elsif h[:unless]
              "unless #{h[:unless]}"
            end

            <<~RUBY
              #{h[:name]} #{condition}
            RUBY
          end

          lines.join("\n")
        end
      end

      rescue_handlers_chunk = if @__rescue_handlers
        lines = @__rescue_handlers.map do |klasses, handler|
          <<~RUBY
          rescue #{klasses.join(", ")} => __e
            #{instance_method(handler).arity == 0 ? handler : "#{handler}(__e)"}
          RUBY
        end

        lines.join("\n")
      else
        ""
      end

      periodic_timers_chunk = if @__periodic_timers
        set_up_periodic_timers

        if action_name == :subscribed
          <<~RUBY
            self.class.__channels << self unless subscription_rejected?
          RUBY
        elsif action_name == :unsubscribed
          <<~RUBY
            self.class.__channels.delete(self)
          RUBY
        end
      else
        ""
      end

      is_subscribing = action_name == :subscribed
      should_release_connections = Rage.config.internal.should_manually_release_ar_connections?

      method_name = class_eval <<~RUBY, __FILE__, __LINE__ + 1
        def __run_#{action_name}(data)
          #{if is_subscribing
            <<~RUBY
              @__is_subscribing = true
            RUBY
          end}

          #{before_subscribe_chunk}
          #{before_unsubscribe_chunk}

          #{if instance_method(action_name).arity == 0
            <<~RUBY
              #{action_name}
            RUBY
          else
            <<~RUBY
              #{action_name}(data)
            RUBY
          end}

          #{after_subscribe_chunk}
          #{after_unsubscribe_chunk}
          #{periodic_timers_chunk}
          #{rescue_handlers_chunk}

          #{if should_release_connections
            <<~RUBY
            ensure
              ActiveRecord::Base.connection_handler.clear_active_connections!(:all)
            RUBY
          end}
        end
      RUBY

      eval("->(channel, data) { channel.#{method_name}(data) }")
    end
    # rubocop:enable all

    # @private
    def __prepare_id_method(method_name)
      define_method(method_name) do
        @__identified_by[method_name]
      end
    end

    # Register a new `before_subscribe` hook that will be called before the {subscribed} method.
    #
    # @example
    #   before_subscribe :my_method
    # @example
    #   before_subscribe do
    #     ...
    #   end
    # @example
    #   before_subscribe :my_method, if: -> { ... }
    def before_subscribe(action_name = nil, **opts, &block)
      add_action(:before_subscribe, action_name, **opts, &block)
    end

    # Register a new `after_subscribe` hook that will be called after the {subscribed} method.
    #
    # @example
    #   after_subscribe do
    #     ...
    #   end
    # @example
    #   after_subscribe :my_method, unless: :subscription_rejected?
    # @note This callback will be triggered even if the subscription was rejected with the {reject} method.
    def after_subscribe(action_name = nil, **opts, &block)
      add_action(:after_subscribe, action_name, **opts, &block)
    end

    # Register a new `before_unsubscribe` hook that will be called before the {unsubscribed} method.
    def before_unsubscribe(action_name = nil, **opts, &block)
      add_action(:before_unsubscribe, action_name, **opts, &block)
    end

    # Register a new `after_unsubscribe` hook that will be called after the {unsubscribed} method.
    def after_unsubscribe(action_name = nil, **opts, &block)
      add_action(:after_unsubscribe, action_name, **opts, &block)
    end

    # Register an exception handler.
    #
    # @param klasses [Class, Array<Class>] exception classes to watch on
    # @param with [Symbol] the name of a handler method. The method can take one argument, which is the raised exception. Alternatively, you can pass a block, which can also take one argument.
    # @example
    #   rescue_from StandardError, with: :report_error
    #
    #   private
    #
    #   def report_error(e)
    #     SomeExternalBugtrackingService.notify(e)
    #   end
    # @example
    #   rescue_from StandardError do |e|
    #     SomeExternalBugtrackingService.notify(e)
    #   end
    def rescue_from(*klasses, with: nil, &block)
      unless with
        if block_given?
          with = define_tmp_method(block)
        else
          raise ArgumentError, "No handler provided. Pass the `with` keyword argument or provide a block."
        end
      end

      if @__rescue_handlers.nil?
        @__rescue_handlers = []
      elsif @__rescue_handlers.frozen?
        @__rescue_handlers = @__rescue_handlers.dup
      end

      @__rescue_handlers.unshift([klasses, with])
    end

    # Set up a timer to periodically perform a task on the channel. Accepts a method name or a block.
    #
    # @param method_name [Symbol, nil] the name of the method to call
    # @param every [Integer] the calling period in seconds
    # @example
    #   periodically every: 3.minutes do
    #     transmit({ action: :update_count, count: current_count })
    #   end
    # @example
    #   periodically :update_count, every: 3.minutes
    def periodically(method_name = nil, every:, &block)
      callback_name = if block_given?
        raise ArgumentError, "Pass the `method_name` argument or provide a block, not both" if method_name
        define_tmp_method(block)
      elsif method_name.is_a?(Symbol)
        define_tmp_method(eval("-> { #{method_name} }"))
      else
        raise ArgumentError, "Expected a Symbol method name, got #{method_name.inspect}"
      end

      unless every.is_a?(Numeric) && every > 0
        raise ArgumentError, "Expected every: to be a positive number of seconds, got #{every.inspect}"
      end

      callback = eval("->(channel) { channel.#{callback_name} }")

      if @__periodic_timers.nil?
        @__periodic_timers = []
      elsif @__periodic_timers.frozen?
        @__periodic_timers = @__periodic_timers.dup
      end

      @__periodic_timers << [callback, every]
    end

    protected

    def set_up_periodic_timers
      return if @__periodic_timers_set_up

      @__channels = Set.new

      @__periodic_timers.each do |callback, every|
        ::Iodine.run_every((every * 1000).to_i) do
          slice_length = (@__channels.length / 20.0).ceil

          if slice_length != 0
            @__channels.each_slice(slice_length) do |slice|
              Fiber.schedule do
                slice.each { |channel| callback.call(channel) }
              rescue => e
                Rage.logger.error("Unhandled exception has occured - #{e.class} (#{e.message}):\n#{e.backtrace.join("\n")}")
              end
            end
          end
        end
      end

      @__periodic_timers_set_up = true
    end

    def add_action(action_type, action_name = nil, **opts, &block)
      if block_given?
        action_name = define_tmp_method(block)
      elsif action_name.nil?
        raise ArgumentError, "No handler provided. Pass the `action_name` parameter or provide a block."
      end

      _if, _unless = opts.values_at(:if, :unless)

      action = {
        name: action_name,
        if: _if,
        unless: _unless
      }

      action[:if] = define_tmp_method(action[:if]) if action[:if].is_a?(Proc)
      action[:unless] = define_tmp_method(action[:unless]) if action[:unless].is_a?(Proc)

      if @__hooks.nil?
        @__hooks = {}
      elsif @__hooks[action_type] && @__hooks.frozen?
        @__hooks = @__hooks.dup
        @__hooks[action_type] = @__hooks[action_type].dup
      end

      if @__hooks[action_type].nil?
        @__hooks[action_type] = [action]
      elsif (i = @__hooks[action_type].find_index { |a| a[:name] == action_name })
        @__hooks[action_type][i] = action
      else
        @__hooks[action_type] << action
      end
    end

    attr_writer :__hooks, :__rescue_handlers, :__periodic_timers

    def inherited(klass)
      klass.__hooks = @__hooks.freeze
      klass.__rescue_handlers = @__rescue_handlers.freeze
      klass.__periodic_timers = @__periodic_timers.freeze
    end

    @@__tmp_name_seed = ("a".."i").to_a.permutation

    def define_tmp_method(block)
      name = @@__tmp_name_seed.next.join
      define_method("__rage_tmp_#{name}", block)
    end
  end # class << self

  # @private
  def __has_action?(action_name)
    !INTERNAL_ACTIONS.include?(action_name) && self.class.__prepared_actions.has_key?(action_name)
  end

  # @private
  def __run_action(action_name, data = nil)
    self.class.__prepared_actions[action_name].call(self, data)
  end

  # @private
  def initialize(connection, params, identified_by)
    @__connection = connection
    @__params = params
    @__identified_by = identified_by
  end

  # Get the params hash passed in during the subscription process.
  #
  # @return [Hash{Symbol=>String,Array,Hash,Numeric,NilClass,TrueClass,FalseClass}]
  def params
    @__params
  end

  # Reject the subscription request. The method should only be called during the subscription
  # process (i.e. inside the {subscribed} method or {before_subscribe}/{after_subscribe} hooks).
  def reject
    @__subscription_rejected = true
  end

  # Checks whether the {reject} method has been called.
  #
  # @return [Boolean]
  def subscription_rejected?
    !!@__subscription_rejected
  end

  # Subscribe to a stream.
  #
  # @param stream [String] the name of the stream
  def stream_from(stream)
    Rage.config.cable.protocol.subscribe(@__connection, stream, @__params)
  end

  # Broadcast data to all the clients subscribed to a stream.
  #
  # @param stream [String] the name of the stream
  # @param data [Object] the data to send to the clients
  # @example
  #   def subscribed
  #     broadcast("notifications", { message: "A new member has joined!" })
  #   end
  def broadcast(stream, data)
    Rage.cable.broadcast(stream, data)
  end

  # Transmit data to the current client.
  #
  # @param data [Object] the data to send to the client
  # @example
  #   def subscribed
  #     transmit({ message: "Hello!" })
  #   end
  def transmit(data)
    message = Rage.config.cable.protocol.serialize(@__params, data)

    if @__is_subscribing
      # we expect a confirmation message to be sent as a result of a successful subscribe call;
      # this will make sure `transmit` calls send data after the confirmation;
      ::Iodine.defer { @__connection.write(message) }
    else
      @__connection.write(message)
    end
  end

  # Called once a client has become a subscriber of the channel.
  def subscribed
  end

  # Called once a client unsubscribes from the channel.
  def unsubscribed
  end
end
