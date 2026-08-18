# frozen_string_literal: true

##
# Converts an enumerable object into a streaming response body. Powers the `render stream:`
# API (see {RageController::API#render}) and is not meant to be used directly. Chunks are
# sent as they are produced using chunked transfer encoding; when the client cannot keep up,
# the producer fiber is parked and resumed once the connection drains.
#
class Rage::Streaming
  # Iodine rejects a single write of 64+ internal ~16KB packets; larger chunks are sliced.
  MAX_WRITE_BYTES = 256 * 1024

  # @param source [#each] an object that yields response chunks; chunks are converted
  #   to strings with `to_s`, `nil` chunks are skipped
  def initialize(source)
    raise ArgumentError, "Streaming body must respond to #each." unless source.respond_to?(:each)

    @source = source
    @log_tags, @log_context = Fiber[:__rage_logger_tags], Fiber[:__rage_logger_context]
  end

  # @private
  # Called by the server with a stream writer once the response is handed off. Runs the
  # producer in a separate fiber so blocking calls in the source don't block the event loop.
  def call(stream)
    Fiber.schedule do
      Iodine.task_inc!
      Fiber[:__rage_logger_tags], Fiber[:__rage_logger_context] = @log_tags, @log_context
      stream_body(stream)
    rescue => e
      Rage.logger.error("Streaming response failed with exception: #{e.class} (#{e.message}):\n#{e.backtrace.join("\n")}")
      Rage::Errors.report(e)
    ensure
      stream.close
      Iodine.task_dec!
    end
  end

  # @private
  # No-op for Rack compatibility: the stream is closed by the producer fiber.
  def close
  end

  private

  # Writes each chunk to the stream. On `:would_block` the producer parks until a wake
  # message ("drain" or "close") and retries; a terminal write status ends the iteration.
  def stream_body(stream)
    producer, parked = Fiber.current, false
    channel = stream.wake_channel

    if channel
      Iodine.subscribe(channel) do
        if parked
          parked = false
          producer.resume if producer.alive?
        end
      end
    end

    @source.each do |chunk|
      next if chunk.nil?
      data = chunk.to_s
      offset = 0

      loop do
        slice = data.bytesize > MAX_WRITE_BYTES ? data.byteslice(offset, MAX_WRITE_BYTES) : data

        loop do
          case stream.write(slice)
          when :ok
            break
          when :would_block
            # no wake channel means the producer can never be resumed: bail out
            return if channel.nil?
            parked = true
            Fiber.defer(-1)
          when :error
            Rage.logger.error("Streaming response terminated: stream.write returned :error")
            return
          else # :closed, :disconnected
            return
          end
        end

        offset += MAX_WRITE_BYTES
        break if offset >= data.bytesize
      end
    end
  ensure
    Iodine.defer { Iodine.unsubscribe(channel) } if channel
  end
end
