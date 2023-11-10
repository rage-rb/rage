# frozen_string_literal: true

require "net/http"
require "digest"
require "pg"
require "mysql2"
require "redis-client"

RSpec.describe Rage::FiberScheduler do
  TEST_HTTP_URL = ENV["TEST_HTTP_URL"]
  TEST_PG_URL = ENV["TEST_PG_URL"]
  TEST_MYSQL_URL = ENV["TEST_MYSQL_URL"]
  TEST_REDIS_URL = ENV["TEST_REDIS_URL"]

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
        database: uri.path[1..-1]
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

  context "with Redis" do
    def redis
      @redis&.close
      @redis = RedisClient.config(url: TEST_REDIS_URL, inherit_socket: true).new_client
    end

    it "correctly reads server info" do
      within_reactor do
        result = redis.call("INFO")
        -> { expect(result).to include("cluster_enabled") }
      end
    end

    it "correctly reads single keys" do
      within_reactor do
        result = redis.call("GET", "mystring")
        -> { expect(Digest::SHA2.hexdigest(result)).to eq("7ba6faccb80b730d15739b58c8751a5a12c9cec86546bdb64756f1c554afb808") }
      end
    end

    it "correctly reads multiple keys" do
      within_reactor do
        results = (1..5).map { |i| redis.call("HGET", "myhash", "key_#{i}") }
        -> { expect(Digest::SHA2.hexdigest(results.join)).to eq("7b885a6b2647baed195eedcf1e367ab37387eca8fdc18762b5382a062d894794") }
      end
    end

    it "correctly writes small keys" do
      within_reactor do
        message = SecureRandom.bytes(2)
        redis.call("SET", "mymessage", message)
        result = redis.call("GET", "mymessage")
        
        -> { expect(result).to eq(message) }
      end
    end

    it "correctly writes large keys" do
      within_reactor do
        message = SecureRandom.bytes(50_000)
        redis.call("SET", "mymessage", message)
        result = redis.call("GET", "mymessage")
        
        -> { expect(result).to eq(message) }
      end
    end

    # context "with timeout" do
    #   let(:redis) { config.new_client(read_timeout: 1) }

    #   it "correctly times out" do
    #     within_reactor do
    #       redis.call("GET", "testkey")
    #       redis.call("BLPOP", "mylist", 0)

    #     rescue => e
    #       -> { expect(e).to be_a(RedisClient::ReadTimeoutError) }
    #     end
    #   end
    # end
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
end
