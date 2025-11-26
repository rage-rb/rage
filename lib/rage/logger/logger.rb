# frozen_string_literal: true

require "logger"

##
# All logs in `rage` consist of two parts: keys and tags. A sample log entry might look like this:
# ```
# [fecbba0735355738] timestamp=2023-10-19T11:12:56+00:00 pid=1825 level=info message=hello
# ```
# In the log entry above, `timestamp`, `pid`, `level`, and `message` are keys, while `fecbba0735355738` is a tag.
#
# Use {tagged} to add custom tags to an entry:
# ```ruby
# Rage.logger.tagged("ApiCall") do
#   perform_api_call
#   Rage.logger.info "success"
# end
# # => [fecbba0735355738][ApiCall] timestamp=2023-10-19T11:12:56+00:00 pid=1825 level=info message=success
# ```
#
# {with_context} can be used to add custom keys:
# ```ruby
# cache_key = "mykey"
# Rage.logger.with_context(cache_key: cache_key) do
#   get_from_cache(cache_key)
#   Rage.logger.info "cache miss"
# end
# # => [fecbba0735355738] timestamp=2023-10-19T11:12:56+00:00 pid=1825 level=info cache_key=mykey message=cache miss
# ```
#
# `Rage::Logger` also implements the interface of Ruby's native {https://ruby-doc.org/3.2.2/stdlibs/logger/Logger.html Logger}:
# ```ruby
# Rage.logger.info("Initializing")
# Rage.logger.debug { "This is a " + potentially + " expensive operation" }
# ```
#
# ## Using the logger
# The recommended approach to logging with Rage is to make sure your code always logs the same message no matter what the input is.
# You can achieve this by using the {with_context} and {tagged} methods. So, a code like this:
# ```ruby
# def process_purchase(user_id:, product_id:)
#   Rage.logger.info "processing purchase with user_id = #{user_id}; product_id = #{product_id}"
# end
# ```
# turns into this:
# ```ruby
# def process_purchase(user_id:, product_id:)
#   Rage.logger.with_context(user_id: user_id, product_id: product_id) do
#     Rage.logger.info "processing purchase"
#   end
# end
# ```
class Rage::Logger
  METHODS_MAP = {
    "debug" => Logger::DEBUG,
    "info" => Logger::INFO,
    "warn" => Logger::WARN,
    "error" => Logger::ERROR,
    "fatal" => Logger::FATAL,
    "unknown" => Logger::UNKNOWN
  }
  private_constant :METHODS_MAP

  attr_reader :level, :formatter

  # @private
  attr_reader :dynamic_tags, :dynamic_context

  # Create a new logger.
  #
  # @param log [Object] a filename (`String`), IO object (typically `STDOUT`, `STDERR`, or an open file), `nil` (it writes nothing) or `File::NULL` (same as `nil`)
  # @param level [Integer] logging severity threshold
  # @param formatter [#call] logging formatter
  # @param shift_age [Integer, String] number of old log files to keep, or frequency of rotation  (`"daily"`, `"weekly"` or `"monthly"`). Default value is `0`, which disables log file rotation
  # @param shift_size [Integer] maximum log file size in bytes (only applies when `shift_age` is a positive Integer)
  # @param shift_period_suffix [String] the log file suffix format for daily, weekly or monthly rotation
  # @param binmode sets whether the logger writes in binary mode
  def initialize(log, level: Logger::DEBUG, formatter: Rage::TextFormatter.new, shift_age: 0, shift_size: 104857600, shift_period_suffix: "%Y%m%d", binmode: false)
    @logdev = if log && log != File::NULL
      Logger::LogDevice.new(log, shift_age:, shift_size:, shift_period_suffix:, binmode:)
    end

    if Rage.env.development? && log.respond_to?(:sync=)
      log.sync = true
    end

    @formatter = formatter
    @level = @logdev ? level : Logger::UNKNOWN
    rebuild!
  end

  # Set the logging severity threshold.
  # @param level [Integer] logging severity threshold
  def level=(level)
    @level = level
    rebuild!
  end

  # Set the logging formatter.
  # @param formatter [#call] logging formatter
  def formatter=(formatter)
    @formatter = formatter
    rebuild!
  end

  # Write the given `msg` to the log with no formatting.
  def <<(msg)
    @logdev&.write(msg)
  end

  # @private
  def dynamic_tags=(dynamic_tags)
    @dynamic_tags = dynamic_tags
    rebuild!
  end

  # @private
  def dynamic_context=(dynamic_context)
    @dynamic_context = dynamic_context
    rebuild!
  end

  # Add custom keys to an entry.
  #
  # @param context [Hash] a hash of custom keys
  # @example
  #   Rage.logger.with_context(key: "mykey") do
  #     Rage.logger.info "cache miss"
  #   end
  def with_context(context)
    old_context = (Thread.current[:rage_logger] ||= { tags: [], context: {} })[:context]

    if old_context.empty? # there's nothing in the context yet
      Thread.current[:rage_logger][:context] = context
    else # it's not the first `with_context` call in the chain
      Thread.current[:rage_logger][:context] = old_context.merge(context)
    end

    yield(self)
  ensure
    Thread.current[:rage_logger][:context] = old_context
  end

  # Add a custom tag to an entry.
  #
  # @param tags [String] the tag to add to an entry
  # @example
  #   Rage.logger.tagged("ApiCall") do
  #     Rage.logger.info "success"
  #   end
  def tagged(*tags)
    old_tags = (Thread.current[:rage_logger] ||= { tags: [], context: {} })[:tags]
    Thread.current[:rage_logger][:tags] = old_tags + tags
    yield(self)
  ensure
    Thread.current[:rage_logger][:tags] = old_tags
  end

  alias_method :with_tag, :tagged

  # Check if the debug level is enabled.
  def debug? = @level <= Logger::DEBUG
  # Check if the error level is enabled.
  def error? = @level <= Logger::ERROR
  # Check if the fatal level is enabled.
  def fatal? = @level <= Logger::FATAL
  # Check if the info level is enabled.
  def info? = @level <= Logger::INFO
  # Check if the warn level is enabled.
  def warn? = @level <= Logger::WARN
  # Check if the unknown level is enabled.
  def unknown? = @level <= Logger::UNKNOWN

  private

  def rebuild!
    methods = METHODS_MAP.map do |level_name, level_val|
      if @logdev.nil? || level_val < @level
        # logging is disabled or the log level is higher than the current one
        <<-RUBY
          def #{level_name}(msg = nil)
            false
          end
        RUBY
      elsif @formatter.class.name.start_with?("Rage::")
        # the call was made from within the application and a built-in formatter is used;
        # in such case we use the `gen_timestamp` method which is much faster than `Time.now.strftime`;
        # it's not a standard approach however, so it's used with built-in formatters only
        <<~RUBY
          def #{level_name}(msg = nil)
            #{with_dynamic_tags_and_context do
              <<~RUBY
                @logdev.write(
                  @formatter.call("#{level_name}".freeze, Iodine::Rack::Utils.gen_timestamp, nil, msg || yield)
                )
              RUBY
            end}
          end
        RUBY
      else
        # the call was made from within the application and a custom formatter is used;
        # stick to the standard approach of using one of the Log Level constants as severity and `Time.now` as time
        <<~RUBY
          def #{level_name}(msg = nil)
            #{with_dynamic_tags_and_context do
              <<~RUBY
                @logdev.write(
                  @formatter.call(#{level_val}, Time.now, nil, msg || yield)
                )
              RUBY
            end}
          end
        RUBY
      end
    end

    self.class.class_eval(methods.join("\n"))
  end

  def with_dynamic_tags_and_context
    do_calls, end_calls = [], []

    if @dynamic_tags
      do_calls << "Rage.logger.tagged(*@dynamic_tags.call) do"
      end_calls << "end"
    end

    if @dynamic_context
      do_calls << "Rage.logger.with_context(@dynamic_context.call) do"
      end_calls << "end"
    end

    "#{do_calls.join("\n")}\n#{yield}\n#{end_calls.join("\n")}"
  end
end
