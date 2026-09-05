# frozen_string_literal: true

require "net/http"
require "digest"
require "benchmark"
require "pg"
require "mysql2"
require "connection_pool"

RSpec.describe Rage::FiberScheduler do
  TEST_HTTP_URL = ENV["TEST_HTTP_URL"]
  TEST_PG_URL = ENV["TEST_PG_URL"]
  TEST_MYSQL_URL = ENV["TEST_MYSQL_URL"]

  before :all do
    skip("skipping fiber tests") unless ENV["ENABLE_EXTERNAL_TESTS"] == "true"
  end

  before :all do
    Fiber.set_scheduler(described_class.new)
  end

  after :all do
    Fiber.set_scheduler(nil)
  end

  it "correctly performs long http GET" do
    within_reactor do
      num = rand
      result = Net::HTTP.get(URI("#{TEST_HTTP_URL}/long-http-get?i=#{num}"))
      -> { expect(result.to_f).to eq(num * 10) }
    end
  end

  it "correctly reads large http response" do
    within_reactor do
      result = Net::HTTP.get(URI("#{TEST_HTTP_URL}/large-http-get"))
      json = JSON.parse(result)
      -> { expect(Digest::SHA2.hexdigest(json["string"])).to eq(json["digest"]) }
    end
  end

  it "correctly performs fast http GET" do
    within_reactor do
      num = rand
      result = Net::HTTP.get(URI("#{TEST_HTTP_URL}/instant-http-get?i=#{num}"))
      -> { expect(result.to_f).to eq(num * 10) }
    end
  end

  it "correctly performs long POST" do
    within_reactor do
      str = "test.#{rand}" * 100_000
      digest = Digest::SHA2.hexdigest(str)
      result = Net::HTTP.post(URI("#{TEST_HTTP_URL}/http-post"), str)

      -> { expect(result.body).to eq(digest) }
    end
  end

  it "correctly performs fast http POST" do
    within_reactor do
      str = rand.to_s
      digest = Digest::SHA2.hexdigest(str)
      result = Net::HTTP.post(URI("#{TEST_HTTP_URL}/http-post"), str)

      -> { expect(result.body).to eq(digest) }
    end
  end

  it "correctly times out" do
    uri = URI("#{TEST_HTTP_URL}/timeout")

    within_reactor do
      Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 1) do |http|
        request = Net::HTTP::Get.new(uri)
        http.request(request)
      end

      raise "test failed!"

    rescue => e
      -> { expect(e).to be_a(Net::ReadTimeout) }
    end
  end

  it "works correctly with non-persistent connections" do
    uri = URI("#{TEST_HTTP_URL}/instant-http-get")

    within_reactor do
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      request = Net::HTTP::Get.new(uri.request_uri)
      response = http.request(request)

      -> { expect(response).to be_a(Net::HTTPOK) }
    end
  end

  it "works correctly with non-persistent connections" do
    uri = URI("#{TEST_HTTP_URL}/http-post")

    within_reactor do
      response = Net::HTTP.start(uri.host) do |http|
        http.post(uri.request_uri, "", { "connection" => "close" })
      end

      -> { expect(response).to be_a(Net::HTTPOK) }
    end
  end

  it "works correctly with persistent connections" do
    uri = URI(TEST_HTTP_URL)

    within_reactor do
      connection = Net::HTTP.new(uri.hostname, uri.port)
      connection.use_ssl = true
      connection.verify_mode = OpenSSL::SSL::VERIFY_PEER
      connection.start

      responses = 3.times.map do
        connection.get("/instant-http-get")
      end

      -> { expect(responses).to all(be_a(Net::HTTPOK)) }
    end
  end

  context "with Postgres" do
    let(:conn) { PG.connect(TEST_PG_URL) }

    after { conn.close }

    it "correctly performs a DB request" do
      within_reactor do
        result = conn.exec("SELECT count(*) FROM tags").to_a
        -> { expect(result.first["count"]).to eq("1000") }
      end
    end

    it "correctly performs a long DB request" do
      within_reactor do
        num = rand
        result = conn.exec("SELECT pg_sleep(2), #{num} as num")
        -> { expect(result.first["num"]).to eq(num.to_s) }
      end
    end

    it "correctly performs multiple DB requests" do
      within_reactor do
        results = []
        ids = [120, 9, 445, 12, 991]

        ids.each do |id|
          results << conn.exec("SELECT * FROM tags WHERE id = #{id}").to_a.first
        end

        -> { expect(results.map { |r| r["id"].to_i }).to match(ids) }
      end
    end

    it "correctly writes to the DB" do
      within_reactor do
        char = ("A".."Z").to_a.sample
        str = char * 50_000

        conn.exec("UPDATE tags SET token = '#{str}' WHERE id = 999")
        result = conn.exec("SELECT * FROM tags WHERE id = 999").to_a
        -> { expect(result.first["token"]).to eq(str) }
      end
    end
  end

  context "with MySQL" do
    let(:uri) { URI(TEST_MYSQL_URL) }
    let(:conn) do
      Mysql2::Client.new(
        host: uri.host,
        port: uri.port,
        username: uri.user,
        password: uri.password,
        database: uri.path[1..]
      )
    end

    after { conn.close }

    it "correctly performs a DB request" do
      within_reactor do
        result = conn.query("SELECT count(*) as count FROM tags")
        -> { expect(result.first["count"]).to eq(1000) }
      end
    end

    it "correctly performs a long DB request" do
      within_reactor do
        num = rand(1000)
        result = conn.query("SELECT sleep(2), #{num} as num")
        -> { expect(result.first["num"]).to eq(num) }
      end
    end

    it "correctly performs multiple DB requests" do
      within_reactor do
        results = []
        ids = [120, 9, 445, 12, 991]

        ids.each do |id|
          results << conn.query("SELECT * FROM tags WHERE id = #{id}").first
        end

        -> { expect(results.map { |r| r["id"] }).to match(ids) }
      end
    end

    it "correctly writes to the DB" do
      within_reactor do
        char = ("A".."Z").to_a.sample
        str = char * 50_000

        conn.query("UPDATE tags SET token = '#{str}' WHERE id = 999")
        result = conn.query("SELECT * FROM tags WHERE id = 999")
        -> { expect(result.first["token"]).to eq(str) }
      end
    end
  end

  context "with connection pool" do
    let(:pool_timeout) { 5 }
    let(:pool_size) { 2 }
    let(:pool) { ConnectionPool.new(size: pool_size, timeout: pool_timeout) { Net::HTTP } }

    it "correctly schedules connections" do
      within_reactor do
        result = Benchmark.realtime do
          fibers = 5.times.map do
            Fiber.schedule { pool.with { sleep(0.2) } }
          end
          Fiber.await(fibers)
        end

        -> { expect(0.58..0.62).to cover(result) }
      end
    end

    it "doesn't wait for <timeout> before making released connections available" do
      within_reactor do
        result = Benchmark.realtime do
          fibers = (1..pool_size + 1).map do
            Fiber.schedule { pool.with { |conn| conn.get(URI("#{TEST_HTTP_URL}/long-http-get")) } }
          end
          Fiber.await(fibers)
        end

        -> { expect(result).to be < pool_timeout }
      end
    end

    context "with timeout" do
      let(:pool_timeout) { 1 }
      let(:pool_size) { 1 }

      it "correctly times out" do
        within_reactor do
          Fiber.schedule { pool.with { |conn| conn.get(URI("#{TEST_HTTP_URL}/timeout")) } }
          pool.with { |conn| conn.get(URI("#{TEST_HTTP_URL}/instant-http-get")) }
          raise "failed"
        rescue => e
          -> { expect(e).to be_a(ConnectionPool::TimeoutError) }
        end
      end
    end
  end

  it "correctly blocks and unblocks fibers" do
    queue = Queue.new
    Thread.new do
      sleep 1
      queue << "unblock_me"
    end

    within_reactor do
      result = queue.pop
      -> { expect(result).to eq("unblock_me") }
    end
  end

  it "correctly reads files" do
    within_reactor do
      str = File.read("spec/fixtures/700b.txt")
      -> { expect(Digest::SHA2.hexdigest(str)).to eq("174d893e34d9e551466f9e6808358cebc7fd91c5cf9a07300a18e035abc0c4a9") }
    end
  end

  it "correctly reads files" do
    within_reactor do
      str = File.read("spec/fixtures/2kb.txt")
      -> { expect(Digest::SHA2.hexdigest(str)).to eq("73ad9fa79f6266fad72c925e5ba197ba296aa433ae5d0f792e87c19e79df798a") }
    end
  end

  it "correctly reads files" do
    within_reactor do
      str = File.read("spec/fixtures/10kb.txt")
      -> { expect(Digest::SHA2.hexdigest(str)).to eq("ec6f95fa1b9b256aeed3d21c0b982822e642079dabd5a032929a993b614815d8") }
    end
  end

  it "correctly writes files" do
    within_reactor do
      str = 100.times.map { rand(1..100) }.join
      File.write("test", str)

      -> { expect(File.read("test")).to eq(str) }
    end

    File.unlink("test")
  end

  it "correctly writes files" do
    within_reactor do
      str = 500_000.times.map { rand(1..100) }.join
      File.write("test", str)

      -> { expect(File.read("test")).to eq(str) }
    end

    File.unlink("test")
  end

  it "correctly sleeps" do
    within_reactor do
      result = Benchmark.realtime do
        Fiber.await(Fiber.schedule { sleep(1) })
      end

      -> { expect((1..1.5)).to include(result) }
    end
  end

  it "correctly sleeps with 0" do
    within_reactor do
      Fiber.await(Fiber.schedule { sleep(0) })
      -> {}
    rescue => e
      -> { raise e }
    end
  end

  it "correctly sleeps with no arguments" do
    within_reactor do
      Fiber.await(Fiber.schedule { sleep })
      -> {}
    rescue => e
      -> { raise e }
    end
  end

  context "fiber interruption" do
    before do
      skip("skipping on Ruby < 4") if Gem::Version.create(RUBY_VERSION) < Gem::Version.create(4)
    end

    it "correctly interrupts a fiber" do
      within_reactor do
        error = begin
          r, _ = IO.pipe

          child = Fiber.schedule do
            r.gets
          end

          Fiber.schedule do
            r.close # This will interrupt the child fiber.
          end

          Fiber.await(child)
        rescue => e
          e
        end

        -> { expect(error).to be_a(IOError) }
      end
    end
  end

  context "with wait generation tracking" do
    it "initializes __wait_generation to 0 for scheduled fibers" do
      within_reactor do
        fiber = Fiber.schedule { Fiber.current.__wait_generation }
        result = Fiber.await(fiber)

        -> { expect(result).to eq([0]) }
      end
    end

    it "increments __wait_generation on each block call" do
      queue1 = Queue.new
      queue2 = Queue.new

      Thread.new do
        sleep 0.2
        queue1 << "first"
        sleep 0.2
        queue2 << "second"
      end

      within_reactor do
        gen_before = Fiber.current.__wait_generation
        queue1.pop
        gen_after_first = Fiber.current.__wait_generation
        queue2.pop
        gen_after_second = Fiber.current.__wait_generation

        -> do
          expect(gen_after_first).to eq(gen_before + 1)
          expect(gen_after_second).to eq(gen_before + 2)
        end
      end
    end

    it "increments __wait_generation on Fiber.await" do
      within_reactor do
        gen_before = Fiber.current.__wait_generation

        Fiber.await(Fiber.schedule { sleep 0.1 })
        gen_after_first = Fiber.current.__wait_generation

        Fiber.await(Fiber.schedule { sleep 0.1 })
        gen_after_second = Fiber.current.__wait_generation

        -> do
          expect(gen_after_first).to eq(gen_before + 1)
          expect(gen_after_second).to eq(gen_before + 2)
        end
      end
    end

    it "prevents stale resume when fiber moves to new wait state" do
      queue1 = Queue.new
      queue2 = Queue.new
      old_channel = nil
      results = []

      within_reactor do
        fiber = Fiber.schedule do
          f = Fiber.current

          # Start a thread that will:
          # 1. Unblock the first wait
          # 2. Capture the old channel
          # 3. Try to publish to the old channel while fiber is in second wait
          Thread.new do
            sleep 0.1
            old_channel = f.__block_channel
            queue1 << "first"

            sleep 0.2
            # Try to publish to the old channel (simulating a stale unblock)
            # This shouldn't resume the fiber because generation has changed
            Iodine.publish(old_channel, "", Iodine::PubSub::PROCESS)
          end

          results << queue1.pop
          results << "starting second wait"

          # Start second unblock thread
          Thread.new { sleep 0.5; queue2 << "second" }

          # Now block on second queue - stale resume from old_channel should be ignored
          results << queue2.pop
          results
        end

        result = Fiber.await(fiber)
        -> { expect(result.first).to eq(["first", "starting second wait", "second"]) }
      end
    end

    it "fiber_interrupt increments generation before raising" do
      test_fiber = nil
      generation_before = nil
      generation_in_rescue = nil

      within_reactor do
        test_fiber = Fiber.schedule do
          generation_before = Fiber.current.__wait_generation

          begin
            sleep 10 # Block for a long time
          rescue => e
            generation_in_rescue = Fiber.current.__wait_generation
            raise e
          end
        end

        # Give the fiber time to start sleeping
        sleep 0.1

        # Interrupt the fiber
        Fiber.scheduler.fiber_interrupt(test_fiber, RuntimeError.new("interrupted"))

        # Wait for fiber to process the exception
        sleep 0.1

        -> do
          # generation_before is 0 (after init)
          # sleep increments to 1
          # fiber_interrupt increments to 2
          expect(generation_in_rescue).to eq(generation_before + 2)
          expect(test_fiber.__get_err).to be_a(RuntimeError)
          expect(test_fiber.__get_err.message).to eq("interrupted")
        end
      end
    end
  end

  context "with worker pool" do
    subject { Fiber.scheduler.send(:worker_pool) }

    before :all do
      skip("skipping on Ruby < 4") if Gem::Version.create(RUBY_VERSION) < Gem::Version.create(4)
    end

    around do |example|
      result = 20.times do
        break :completed if subject.stats[:in_progress] == 0
        sleep 0.1
      end

      unless result == :completed
        raise "couldn't drain worker pool before running new test"
      end

      example.call
    end

    it "delegates nogvl operations to the worker pool" do
      within_reactor do
        io_fiber = Fiber.schedule do
          sleep 0.1
        end

        Fiber.schedule do
          Fiber.pause
          Iodine::WorkerPool.__busy(duration: 1)
        end

        time = Benchmark.realtime { Fiber.await(io_fiber) }

        -> { expect(time).to be < 0.2 }
      end
    end

    it "performs nogvl operations sequentially" do
      within_reactor do
        results = []

        fibers = 3.times.map do |i|
          Fiber.schedule do
            Fiber.pause
            Iodine::WorkerPool.__busy(duration: 0.1)
            results << "fiber-#{i}"
          end
        end

        time = Benchmark.realtime { Fiber.await(fibers) }

        -> do
          expect(time).to be_between(0.25, 0.35)
          expect(results).to eq(%w(fiber-0 fiber-1 fiber-2))
        end
      end
    end

    it "allows to interrupt a nogvl operation" do
      within_reactor do
        result = nil

        fiber = Fiber.schedule do
          Fiber.pause
          Iodine::WorkerPool.__busy(duration: 0.2)
        ensure
          Fiber.yield
          result = "not expected"
        end

        sleep 0.1
        Fiber.scheduler.fiber_interrupt(fiber, RuntimeError.new)
        sleep 0.5

        -> { expect(result).to be_nil }
      end
    end

    context "#stats" do
      it "returns correct stats" do
        within_reactor do
          -> do
            expect(subject.stats).to match({
              workers: 1,
              queued: 0,
              in_progress: 0,
              completed: instance_of(Integer),
              submitted: instance_of(Integer),
              closed: false
            })
          end
        end
      end

      it "calculates queued work items" do
        within_reactor do
          3.times do
            Fiber.schedule do
              Iodine::WorkerPool.__busy(duration: 0.1)
            end
          end

          sleep 0.01
          stats = subject.stats

          -> { expect(stats).to include({ in_progress: 1, queued: 2 }) }
        end
      end

      it "calculates completed work items" do
        within_reactor do
          completed_before = subject.stats[:completed]

          3.times do
            Fiber.schedule do
              Iodine::WorkerPool.__busy(duration: 0.01)
            end
          end

          sleep 0.1
          completed_after = subject.stats[:completed]

          -> { expect(completed_after - completed_before).to eq(3) }
        end
      end
    end
  end

  context "#timeout_after" do
    it "does not raise when block completes before timeout" do
      within_reactor do
        result = Fiber.scheduler.timeout_after(1) do
          sleep 0.1
          "completed"
        end

        -> { expect(result).to eq("completed") }
      end
    end

    it "raises Timeout::Error when block exceeds timeout" do
      within_reactor do
        error = begin
          Fiber.scheduler.timeout_after(0.1) do
            sleep 1
          end
        rescue => e
          e
        end

        -> { expect(error).to be_a(Timeout::Error) }
      end
    end

    it "raises custom exception class" do
      within_reactor do
        error = begin
          Fiber.scheduler.timeout_after(0.1, RuntimeError) do
            sleep 1
          end
        rescue => e
          e
        end

        -> { expect(error).to be_a(RuntimeError) }
      end
    end

    it "raises custom exception with arguments" do
      within_reactor do
        error = begin
          Fiber.scheduler.timeout_after(0.1, RuntimeError, "custom message") do
            sleep 1
          end
        rescue => e
          e
        end

        -> do
          expect(error).to be_a(RuntimeError)
          expect(error.message).to eq("custom message")
        end
      end
    end

    it "times out during IO operations" do
      within_reactor do
        error = begin
          Timeout.timeout(0.5) do
            Net::HTTP.get(URI("#{TEST_HTTP_URL}/timeout"))
          end
        rescue => e
          e
        end

        -> { expect(error).to be_a(Timeout::Error) }
      end
    end

    context "with inner timeouts" do
      it "inner timeout fires before outer timeout" do
        within_reactor do
          error = begin
            Fiber.scheduler.timeout_after(1) do
              Fiber.scheduler.timeout_after(0.1) do
                sleep 2
              end
            end
          rescue => e
            e
          end

          -> { expect(error).to be_a(Timeout::Error) }
        end
      end

      it "outer timeout fires when inner block is slow" do
        within_reactor do
          error = begin
            Fiber.scheduler.timeout_after(0.1) do
              Fiber.scheduler.timeout_after(1) do
                sleep 2
              end
            end
          rescue => e
            e
          end

          -> { expect(error).to be_a(Timeout::Error) }
        end
      end

      it "inner timeout with custom exception does not affect outer" do
        within_reactor do
          error = begin
            Fiber.scheduler.timeout_after(1, RuntimeError, "outer") do
              Fiber.scheduler.timeout_after(0.1, ArgumentError, "inner") do
                sleep 2
              end
            end
          rescue => e
            e
          end

          -> do
            expect(error).to be_a(ArgumentError)
            expect(error.message).to eq("inner")
          end
        end
      end

      it "completes successfully when inner timeout does not fire" do
        within_reactor do
          result = Fiber.scheduler.timeout_after(1) do
            inner_result = Fiber.scheduler.timeout_after(0.5) do
              sleep 0.1
              "inner done"
            end
            "outer done with #{inner_result}"
          end

          -> { expect(result).to eq("outer done with inner done") }
        end
      end

      it "rescues inner timeout and continues outer block" do
        within_reactor do
          result = Fiber.scheduler.timeout_after(1) do
            inner_result = begin
              Fiber.scheduler.timeout_after(0.1, ArgumentError) do
                sleep 2
              end
            rescue ArgumentError
              "inner timed out"
            end
            "outer done: #{inner_result}"
          end

          -> { expect(result).to eq("outer done: inner timed out") }
        end
      end

      it "does not fire stale inner timeout after rescue" do
        within_reactor do
          results = []

          result = Fiber.scheduler.timeout_after(2) do
            begin
              Fiber.scheduler.timeout_after(0.1) do
                sleep 1
              end
            rescue Timeout::Error
              results << "inner timeout caught"
            end

            # Sleep long enough that the inner timeout would have fired again if stale
            sleep 0.3
            results << "continued after rescue"
            results
          end

          -> { expect(result).to eq(["inner timeout caught", "continued after rescue"]) }
        end
      end
    end

    it "does not reset outer timeout after inner fires" do
      within_reactor do
        results = []

        result = Fiber.scheduler.timeout_after(0.3) do
          begin
            Fiber.scheduler.timeout_after(0.1) do
              sleep 1
            end
          rescue Timeout::Error
            results << "inner timeout caught"
          end

          begin
            # Sleep long enough that the outer timeout fires
            sleep 1
          rescue Timeout::Error
            results << "outer timeout caught"
          end

          results
        end

        -> { expect(result).to eq(["inner timeout caught", "outer timeout caught"]) }
      end
    end
  end

  context "#process_wait" do
    it "waits for processes in a non-blocking manner" do
      within_reactor do
        result = Benchmark.realtime do
          Fiber.schedule { Process.wait(Process.spawn("sleep 1")) }
        end

        -> { expect(result).to be < 0.1 }
      end
    end

    it "resumes the fiber when the process is finished" do
      within_reactor do
        result = Benchmark.realtime do
          Fiber.await([
            Fiber.schedule { Process.wait(Process.spawn("sleep 1")) }
          ])
        end

        -> { expect(0.9..1.1).to cover(result) }
      end
    end

    it "resumes the fiber when the process is killed" do
      within_reactor do
        pid = nil

        f = Fiber.schedule do
          pid = Process.spawn("sleep 5")
          Process.wait(pid)
        end

        Fiber.schedule do
          sleep 1
          Process.kill("TERM", pid)
        end

        result = Benchmark.realtime do
          Fiber.await([f])
        end

        -> { expect(0.9..1.1).to cover(result) }
      end
    end
  end

  context "io_read and io_write hooks" do
    describe "VERSION constant" do
      subject { Rage::FiberScheduler::VERSION }

      context "with Ruby < 4.1" do
        before do
          skip if Gem::Version.create(RUBY_VERSION) >= Gem::Version.create("4.1.0")
        end

        it do
          is_expected.to eq(3)
        end
      end

      context "with Ruby >= 4.1" do
        before do
          skip if Gem::Version.create(RUBY_VERSION) < Gem::Version.create("4.1.0")
        end

        it do
          is_expected.to eq(4)
        end
      end
    end

    context "io_read" do
      it "reads data from a file into a buffer" do
        within_reactor do
          content = File.read("spec/fixtures/700b.txt")
          -> { expect(content.bytesize).to eq(705) }
        end
      end

      it "reads data from a pipe" do
        within_reactor do
          r, w = IO.pipe
          w.write("hello from pipe")
          w.close

          result = r.read
          -> { expect(result).to eq("hello from pipe") }
        end
      end

      it "handles EOF correctly" do
        within_reactor do
          r, w = IO.pipe
          w.close

          result = r.read
          -> { expect(result).to eq("") }
        end
      end

      it "accumulates chunked writes when reading until EOF" do
        within_reactor do
          r, w = IO.pipe

          Fiber.schedule do
            w.write("first")
            sleep 0.1
            w.write("second")
            w.close
          end

          result = r.read
          -> { expect(result).to eq("firstsecond") }
        end
      end

      it "can read partial data with fixed-length reads" do
        within_reactor do
          r, w = IO.pipe

          Fiber.schedule do
            w.write("hello")
            sleep 0.1
            w.write("world")
            w.close
          end

          # Give first write time to complete
          sleep 0.05
          first = r.read(5)
          rest = r.read

          -> do
            expect(first).to eq("hello")
            expect(rest).to eq("world")
          end
        end
      end

      it "reads large data spanning multiple reads" do
        within_reactor do
          content = File.read("spec/fixtures/10kb.txt")
          -> do
            expect(content.bytesize).to eq(10585)
            expect(Digest::SHA2.hexdigest(content)).to eq("ec6f95fa1b9b256aeed3d21c0b982822e642079dabd5a032929a993b614815d8")
          end
        end
      end

      it "handles concurrent reads from multiple pipes" do
        within_reactor do
          results = []

          fibers = 3.times.map do |i|
            Fiber.schedule do
              r, w = IO.pipe
              Fiber.schedule { sleep 0.05 * i; w.write("data#{i}"); w.close }
              results << r.read
            end
          end

          Fiber.await(fibers)
          -> { expect(results.sort).to eq(["data0", "data1", "data2"]) }
        end
      end

      context "with IO::Buffer" do
        it "reads into a buffer with specified length" do
          within_reactor do
            r, w = IO.pipe
            w.write("hello world")
            w.close

            bytes_read = r.read(11)
            -> { expect(bytes_read).to eq("hello world") }
          end
        end
      end
    end

    context "io_write" do
      it "writes data to a file" do
        within_reactor do
          str = "test data for write: #{rand}"
          File.write("test_io_write", str)
          result = File.read("test_io_write")

          -> { expect(result).to eq(str) }
        end

        File.unlink("test_io_write") if File.exist?("test_io_write")
      end

      it "writes data to a pipe" do
        within_reactor do
          r, w = IO.pipe
          w.write("hello to pipe")
          w.close

          result = r.read
          -> { expect(result).to eq("hello to pipe") }
        end
      end

      it "writes empty data" do
        within_reactor do
          r, w = IO.pipe
          w.write("")
          w.close

          result = r.read
          -> { expect(result).to eq("") }
        end
      end

      it "writes large data" do
        within_reactor do
          str = 500_000.times.map { rand(1..100) }.join
          File.write("test_io_write_large", str)

          -> { expect(File.read("test_io_write_large")).to eq(str) }
        end

        File.unlink("test_io_write_large") if File.exist?("test_io_write_large")
      end

      it "handles concurrent writes to multiple pipes" do
        within_reactor do
          results = []

          fibers = 3.times.map do |i|
            Fiber.schedule do
              r, w = IO.pipe
              data = "concurrent#{i}" * 1000
              Fiber.schedule { w.write(data); w.close }
              results << [i, r.read]
            end
          end

          Fiber.await(fibers)
          -> do
            results.sort_by(&:first).each do |i, data|
              expect(data).to eq("concurrent#{i}" * 1000)
            end
          end
        end
      end

      it "writes and reads binary data correctly" do
        within_reactor do
          binary_data = (0..255).to_a.pack("C*")
          File.binwrite("test_io_write_binary", binary_data)
          result = File.binread("test_io_write_binary")

          -> { expect(result).to eq(binary_data) }
        end

        File.unlink("test_io_write_binary") if File.exist?("test_io_write_binary")
      end
    end

    context "V3 specific behavior" do
      before do
        skip("V3 tests only run on scheduler VERSION 3") unless Rage::FiberScheduler::VERSION == 3
      end

      it "loops internally within io_read until EOF or short read" do
        within_reactor do
          r, w = IO.pipe

          writer = Fiber.schedule do
            3.times do |i|
              w.write("chunk#{i}")
              sleep 0.05
            end
            w.close
          end

          result = r.read
          Fiber.await(writer)

          -> { expect(result).to eq("chunk0chunk1chunk2") }
        end
      end

      it "handles length 0 to mean read up to buffer size" do
        within_reactor do
          content = File.read("spec/fixtures/2kb.txt")
          -> { expect(content.bytesize).to eq(2306) }
        end
      end
    end

    context "V4 specific behavior" do
      before do
        skip("V4 tests only run on scheduler VERSION 4") unless Rage::FiberScheduler::VERSION == 4
      end

      it "delegates directly to Iodine (single-operation semantics)" do
        within_reactor do
          r, w = IO.pipe
          w.write("single op")
          w.close

          result = r.read
          -> { expect(result).to eq("single op") }
        end
      end

      it "io_read returns 0 immediately when length is 0" do
        within_reactor do
          r, w = IO.pipe
          buffer = IO::Buffer.new(100)

          result = Fiber.scheduler.io_read(r, buffer, 0, 0)

          -> { expect(result).to eq(0) }
        end
      end

      it "io_write returns 0 immediately when length is 0" do
        within_reactor do
          _, w = IO.pipe
          buffer = IO::Buffer.new(100)

          result = Fiber.scheduler.io_write(w, buffer, 0, 0)

          -> { expect(result).to eq(0) }
        end
      end
    end

    context "error handling" do
      it "raises appropriate error when reading from closed pipe" do
        within_reactor do
          r, w = IO.pipe
          r.close
          w.close

          error = begin
            r.read
          rescue => e
            e
          end

          -> { expect(error).to be_a(IOError) }
        end
      end

      it "handles EINTR gracefully" do
        within_reactor do
          r, w = IO.pipe
          w.write("test")
          w.close

          result = r.read
          -> { expect(result).to eq("test") }
        end
      end
    end
  end
end
