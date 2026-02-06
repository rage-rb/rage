##
# JSON formatter for Rage logger.
#
# Produces log lines in JSON format, including tags, context, and request details if available.
#
# Example log line:
#
# ```json
# {"tags":["fecbba0735355738"],"timestamp":"2025-10-19T11:12:56+00:00","pid":"1825","level":"info","method":"GET","path":"/api/v1/resource","controller":"Api::V1::ResourceController","action":"index","status":200,"duration":0.15}
# ```
#
# Use {Rage.configure Rage.configure} to set the formatter:
#
# ```ruby
# Rage.configure do |config|
#   config.log_formatter = Rage::JSONFormatter.new
# end
# ```
#
class Rage::JSONFormatter
  def initialize
    @pid = Process.pid.to_s
    Iodine.on_state(:on_start) do
      @pid = Process.pid.to_s
    end
  end

  def call(severity, timestamp, _, message)
    tags, context = Fiber[:__rage_logger_tags] || [], Fiber[:__rage_logger_context] || {}

    if !context.empty?
      context_msg = ""
      context.each { |k, v| context_msg << "\"#{k}\":#{v.to_json}," }
    end

    tags_msg = if tags.length == 1
      "{\"tags\":[\"#{tags[0]}\"],"
    elsif tags.length == 2
      "{\"tags\":[\"#{tags[0]}\",\"#{tags[1]}\"],"
    elsif tags.length == 0
      "{"
    else
      msg = "{\"tags\":[\"#{tags[0]}\",\"#{tags[1]}\""
      i = 2
      while i < tags.length
        msg << ",\"#{tags[i]}\""
        i += 1
      end
      msg << "],"
    end

    if (final = Fiber[:__rage_logger_final])
      params, env = final[:params], final[:env]
      if params && params[:controller]
        return "#{tags_msg}\"timestamp\":\"#{timestamp}\",\"pid\":\"#{@pid}\",\"level\":\"info\",\"method\":\"#{env["REQUEST_METHOD"]}\",\"path\":\"#{env["PATH_INFO"]}\",\"controller\":\"#{Rage::Router::Util.path_to_name(params[:controller])}\",\"action\":\"#{params[:action]}\",#{context_msg}\"status\":#{final[:response][0]},\"duration\":#{final[:duration]}}\n"
      else
        # no controller/action keys are written if there are no params
        return "#{tags_msg}\"timestamp\":\"#{timestamp}\",\"pid\":\"#{@pid}\",\"level\":\"info\",\"method\":\"#{env["REQUEST_METHOD"]}\",\"path\":\"#{env["PATH_INFO"]}\",#{context_msg}\"status\":#{final[:response][0]},\"duration\":#{final[:duration]}}\n"
      end
    end

    "#{tags_msg}\"timestamp\":\"#{timestamp}\",\"pid\":\"#{@pid}\",\"level\":\"#{severity}\",#{context_msg}\"message\":\"#{message}\"}\n"
  end
end
