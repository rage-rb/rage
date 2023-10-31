Rage.configure do
  # Specify the number of server processes to run. Defaults to number of CPU cores.
  # config.server.workers_count = ENV.fetch("WEB_CONCURRENCY", 1)

  # Specify the port the server will listen on.
  config.server.port = 3000
end
