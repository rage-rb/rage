# frozen_string_literal: true

require "websocket-client-simple"

module WebSocketHelper
  def with_websocket_connection(url, headers: {})
    client = WebSocketTestClient.new(url, headers:)
    yield client if block_given?
    client
  end

  class WebSocketTestClient
    def initialize(url, headers: {})
      @url = url
      @headers = headers

      ws_data = { connected: false, closed: false, heartbeats: [], messages: [] }

      @ws = WebSocket::Client::Simple.connect(@url, headers: @headers) do |ws|
        ws.on :open do
          ws_data[:connected] = true
          ws_data[:closed] = false
        end

        ws.on :message do |msg|
          list = msg.to_s.include?("ping") ? ws_data[:heartbeats] : ws_data[:messages]
          list << msg.to_s
        end

        ws.on :close do
          ws_data[:closed] = true
        end
      end

      @ws_data = ws_data

      sleep 0.1
    end

    def connected?
      @ws.handshake.valid? && @ws_data[:connected] && !@ws_data[:closed]
    end

    def send(data)
      2.times do
        @ws.send(data)
        break
      rescue Errno::EBADF
        puts "Lost websocket connection! Reconnecting..."
        @ws.connect(@url, headers: @headers)
      end

      sleep 0.1
    end

    def heartbeats
      @ws_data[:heartbeats]
    end

    def messages
      @ws_data[:messages]
    end
  end
end
