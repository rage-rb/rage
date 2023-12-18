require "net/http"

class AsyncController < RageController::API
  def sum
    i1 = Net::HTTP.get(URI("#{ENV["TEST_HTTP_URL"]}/instant-http-get?i=#{5.7}"))
    i2 = Net::HTTP.get(URI("#{ENV["TEST_HTTP_URL"]}/instant-http-get?i=#{3.4}"))
    i3, i4 = Fiber.await([
      Fiber.schedule { Net::HTTP.get(URI("#{ENV["TEST_HTTP_URL"]}/instant-http-get?i=#{1.8}")) },
      Fiber.schedule { Net::HTTP.get(URI("#{ENV["TEST_HTTP_URL"]}/instant-http-get?i=#{8.3}")) },
    ])

    render plain: i1.to_i + i2.to_i + i3.to_i + i4.to_i
  end

  def long
    response = Net::HTTP.get(URI("#{ENV["TEST_HTTP_URL"]}/long-http-get?i=#{params[:i]}"))
    render plain: response
  end

  def empty
    Net::HTTP.get(URI("#{ENV["TEST_HTTP_URL"]}/instant-http-get?i=#{rand}"))
  end

  def raise_error
    f = Fiber.schedule do
      sleep 0.1
      raise "raised from inner fiber"
    end
    Fiber.await f
  end
end
