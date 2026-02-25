# frozen_string_literal: true

class CLISkills < Thor
  SKILLS_DIR = "rage-framework"
  VERSION_FILE = ".version"

  desc "install", "Install skills for coding agents"
  option :verbose, desc: "Debug output"
  def install
    installation_path = choose_installation_path
    return unless installation_path

    skills_version = fetch_skills_version
    say "Downloading skills..."
    install_skills(installation_path, skills_version)

    say "\nInstalled Rage skills #{skills_version} to #{set_color(installation_path, :bold)}."
    say "Skills are now available to your coding agent."
  rescue => e
    say_error(e)
  end

  desc "update", "Update installed skills"
  option :verbose, desc: "Debug output"
  option :json, type: :boolean, desc: "Output JSON for programmatic use"
  def update
    skills_destinations = Dir.glob(".*/skills/#{SKILLS_DIR}")
    debug { "Existing skills installations found: #{skills_destinations}" }

    if skills_destinations.empty?
      log "No existing installation found. Running fresh install...\n\n"
      return install
    end

    skills_version = fetch_skills_version
    updated_paths = []

    skills_destinations.each do |destination|
      version_file = File.join(destination, VERSION_FILE)
      current_version = File.exist?(version_file) ? File.read(version_file).strip : nil

      if current_version == skills_version
        log "#{destination}: already up to date."
        next
      end

      log "Updating #{destination}..."
      install_skills(destination, skills_version)
      updated_paths << destination
    end

    if updated_paths.any?
      log "\nUpdated #{updated_paths.size} installation#{"s" if updated_paths.size > 1} to #{skills_version}."
    end

    json_output(
      status: updated_paths.any? ? "updated" : "up_to_date",
      version: skills_version,
      paths: skills_destinations
    )
  rescue => e
    if options[:json]
      json_output(status: "error", message: e.message)
      exit 1
    else
      say_error(e)
    end
  end

  no_commands do
    def debug
      puts("* #{yield}") if options[:verbose]
    end

    def log(message)
      if options[:json]
        warn(message)
      else
        say(message)
      end
    end

    def json_output(data)
      return unless options[:json]
      require "json"
      puts JSON.generate(data)
    end

    def say_error(error)
      say "#{set_color("Error:", :red, :bold)} #{error.message}"
      debug { "#{error.class}: #{error.message}\n#{error.backtrace.join("\n")}" }
    end

    def choose_installation_path
      agent_options = [
        ["1", "Claude Code", ".claude/skills"],
        ["2", "GitHub Copilot", ".github/skills"],
        ["3", "Cursor", ".cursor/skills"],
        ["4", "Amp/Codex", ".agents/skills"],
        ["5", "Antigravity", ".agent/skills"],
        ["6", "Gemini CLI", ".gemini/skills"],
        ["7", "Windsurf", ".windsurf/skills"],
        ["8", "OpenCode", ".opencode/skills"],
        ["9", "Other", ".claude/skills"]
      ]

      print_table([["Option", "Coding Agent", "Installation Path"]] + agent_options)
      agent_choice = ask("\nSelect your coding agent (1-#{agent_options[-1][0]}):", default: "1")

      installation_path = ".claude/skills"

      agent_options.each do |option, agent, path|
        if agent_choice == option || agent.downcase.include?(agent_choice.downcase)
          installation_path = path
          break
        end
      end

      say "\nSource: #{set_color("https://github.com/rage-rb/skills", :bold)}"
      say "Destination: #{set_color(installation_path, :bold)}"

      answer = ask("Proceed with installation? [Y/n]", default: "y")
      unless answer.downcase.start_with?("y")
        say "Installation cancelled."
        return nil
      end

      File.join(installation_path, SKILLS_DIR)
    end

    def fetch_skills_version
      require "json"

      manifest = begin
        JSON.parse(fetch("https://rage-rb.github.io/skills/manifest.json"))
      rescue => e
        debug { "#{e.class} (#{e.message}):\n#{e.backtrace.join("\n")}" }
        raise "Could not download skills manifest. Please check your network connection."
      end

      major, minor, _ = Rage::VERSION.split(".").map(&:to_i)

      debug { "Rage::VERSION: #{Rage::VERSION}; Manifest: #{manifest["versions"]}" }

      # Find the closest matching version: same major, highest minor <= current
      matched_major, matched_minor = manifest["versions"].
        keys.
        map { |v| v.split(".").map(&:to_i) }.
        select { |_major, _| _major == major }.
        select { |_, _minor| _minor <= minor }.
        max_by { |_, _minor| _minor }

      if matched_major && matched_minor
        manifest["versions"]["#{matched_major}.#{matched_minor}"]
      else
        raise "No skills available for Rage #{major}.x."
      end
    end

    def install_skills(installation_path, version)
      require "zlib"
      require "rubygems/package"
      require "fileutils"
      require "stringio"
      require "digest"

      Thread.report_on_exception = false

      artifact_request = Thread.new { fetch("https://github.com/rage-rb/skills/releases/download/#{version}/skills.tar.gz") }
      checksum_request = Thread.new { fetch("https://github.com/rage-rb/skills/releases/download/#{version}/checksums.txt") }

      artifact, checksum = artifact_request.value, checksum_request.value

      if artifact.nil? || checksum.nil?
        raise "Could not download the skills package. Please check your network connection and try again."
      end

      sha, _ = checksum.split
      if Digest::SHA256.hexdigest(artifact) != sha
        raise "Download verification failed. Please try again."
      end

      destination = File.expand_path(installation_path)
      FileUtils.mkdir_p(destination)

      # Clear existing contents but keep the directory intact
      Dir.children(destination).each do |child|
        debug { "Removing #{child}" }
        FileUtils.rm_rf(File.join(destination, child))
      end

      Zlib::GzipReader.wrap(StringIO.new(artifact)) do |gz|
        Gem::Package::TarReader.new(gz) do |tar|
          tar.each do |entry|
            path = File.join(destination, entry.full_name)

            unless File.expand_path(path).start_with?("#{destination}/")
              raise "Invalid archive: contains files outside the destination directory."
            end

            if entry.directory?
              debug { "Created directory #{entry.full_name}" }
              FileUtils.mkdir_p(path)
            elsif entry.file?
              debug { "Written file #{entry.full_name}" }
              FileUtils.mkdir_p(File.dirname(path))
              File.binwrite(path, entry.read)
            end
          end
        end
      end

      File.write(File.join(destination, VERSION_FILE), version)
    end

    def fetch(uri, retries = 2)
      response = request(uri)
      return response if response

      retries > 0 ? fetch(uri, retries - 1) : nil
    end

    def request(uri, limit = 3)
      require "net/http"

      raise "Too many HTTP redirects" if limit == 0

      debug { "Fetching #{uri[0..100]}" }

      parsed_uri = URI(uri)
      http = Net::HTTP.new(parsed_uri.host, parsed_uri.port)
      http.use_ssl = parsed_uri.scheme == "https"
      http.open_timeout = 5
      http.read_timeout = 5

      response = http.request(Net::HTTP::Get.new(parsed_uri))

      case response
      when Net::HTTPSuccess
        response.body.force_encoding("ASCII-8BIT")
      when Net::HTTPRedirection
        debug { "Redirected to #{response["Location"][0..100]}" }
        request(response["Location"], limit - 1)
      end
    end
  end
end
