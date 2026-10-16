# frozen_string_literal: true

require "websocket"
require "socket"
require "uri"

module WebSocketHelper
  def create_ws_client(...)
    client = WebSocketClient.new(...)

    if block_given?
      yield client
      client.close
    end

    client
  end

  class WebSocketClient
    DEFAULT_TIMEOUT = ENV["GITHUB_ACTIONS"] ? 5 : 2
    DEFAULT_HEADERS = { Origin: "localhost:3000" }.freeze

    attr_reader :last_message

    def initialize(url, headers: DEFAULT_HEADERS)
      @url = url
      @headers = headers
      @closed = false
      @incoming_frame = nil
      @last_message = nil

      uri = URI.parse(url)
      @socket = TCPSocket.new(uri.host, uri.port || 80)

      perform_handshake
    end

    def connected?
      @handshake.valid? && !@closed
    end

    def send(data)
      frame = WebSocket::Frame::Outgoing::Client.new(
        version: @handshake.version,
        data: data,
        type: :text
      )
      @socket.write(frame.to_s)
    end

    def receive(timeout: DEFAULT_TIMEOUT, heartbeat: false)
      message = receive_one(timeout:)

      if message.to_s.include?("ping") && !heartbeat
        receive(timeout:)
      elsif message
        @last_message = message
      end
    end

    def close
      return if @closed

      frame = WebSocket::Frame::Outgoing::Client.new(
        version: @handshake.version,
        type: :close
      )
      @socket.write(frame.to_s) rescue nil
      @socket.close rescue nil
      @closed = true
    end

    private

    def perform_handshake
      @handshake = WebSocket::Handshake::Client.new(url: @url, headers: @headers)
      @socket.write(@handshake.to_s)

      loop do
        if IO.select([@socket], nil, nil, 5)
          data = @socket.read_nonblock(4096, exception: false)
          break if data.nil? || data == :wait_readable || data.empty?

          @handshake << data
          break if @handshake.finished?
        else
          raise "Handshake timeout"
        end
      end
    end

    def receive_one(timeout:)
      @incoming_frame ||= WebSocket::Frame::Incoming::Client.new(version: @handshake.version)

      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout

      loop do
        if (frame = @incoming_frame.next)
          case frame.type
          when :text, :binary
            return frame.to_s
          when :ping
            send_pong(frame.data)
          when :close
            @closed = true
            return :closed
          end
        end

        remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
        return nil if remaining <= 0

        if IO.select([@socket], nil, nil, remaining)
          data = @socket.read_nonblock(4096, exception: false)
          if data.nil? || data == :wait_readable
            next
          elsif data.empty?
            @closed = true
            return :closed
          else
            @incoming_frame << data
          end
        else
          return nil
        end
      end
    end

    def send_pong(data)
      frame = WebSocket::Frame::Outgoing::Client.new(
        version: @handshake.version,
        data: data,
        type: :pong
      )
      @socket.write(frame.to_s)
    end
  end
end
