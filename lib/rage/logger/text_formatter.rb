class Rage::TextFormatter
  def initialize
    @pid = Process.pid
    Iodine.on_state(:on_start) do
      @pid = Process.pid
    end
  end

  def call(severity, timestamp, _, message)
    logger = Thread.current[:rage_logger]
    tags, context = logger[:tags], logger[:context]

    if !context.empty?
      context_msg = ""
      context.each { |k, v| context_msg << "#{k}=#{v} " }
    end

    if final = logger[:final]
      params, env = final[:params], final[:env]
      if params
        return "[#{tags[0]}] timestamp=#{timestamp} pid=#{@pid} level=info method=#{env["REQUEST_METHOD"]} path=#{env["PATH_INFO"]} controller=#{params[:controller]} action=#{params[:action]} #{context_msg}status=#{final[:response][0]} duration=#{final[:duration]}\n"
      else
        # no controller/action keys are written if there are no params
        return "[#{tags[0]}] timestamp=#{timestamp} pid=#{@pid} level=info method=#{env["REQUEST_METHOD"]} path=#{env["PATH_INFO"]} #{context_msg}status=#{final[:response][0]} duration=#{final[:duration]}\n"
      end
    end

    if tags.length == 1
      tags_msg = "[#{tags[0]}] timestamp=#{timestamp} pid=#{@pid} level=#{severity}"
    elsif tags.length == 2
      tags_msg = "[#{tags[0]}][#{tags[1]}] timestamp=#{timestamp} pid=#{@pid} level=#{severity}"
    else
      tags_msg = "[#{tags[0]}][#{tags[1]}]"
      i = 2
      while i < tags.length
        tags_msg << "[#{tags[i]}]"
        i += 1
      end
      tags_msg << " timestamp=#{timestamp} pid=#{@pid} level=#{severity}"
    end

    "#{tags_msg} #{context_msg}message=#{message}\n"
  end
end
