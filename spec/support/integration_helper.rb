# frozen_string_literal: true

module IntegrationHelper
  def launch_server(env: {})
    Bundler.with_unbundled_env do
      system("gem build -o rage-local.gem && gem install rage-local.gem --no-document && bundle install")
      @pid = spawn(env, "bundle exec rage s", chdir: "spec/integration/test_app")
      sleep(1)
    end
  end

  def stop_server
    if @pid
      Process.kill(:SIGTERM, @pid)
      Process.wait
      system("rm spec/integration/test_app/Gemfile.lock")
      system("rm spec/integration/test_app/log/development.log")
    end
  end
end
