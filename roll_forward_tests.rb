#!/usr/bin/env ruby -w

require "minitest/autorun"

Dir.chdir(__dir__)

require "tempfile"

RHTTP_REPO = "rhttp_repo"

# Do we want a cleanup via "pgrep -f 4321" and killing all resulting processes?

def with_cmd_out_and_err cmd: "curl -v http://localhost:4321", verbose: false
  outfile = Tempfile.new("rebuilding_http_test_out")
  errfile = Tempfile.new("rebuilding_http_test_err")

  pid = spawn cmd, out: [outfile.path, "w"], err: [errfile.path, "w"]
  Process.wait pid

  if $?.success?
    # Ran without error, no problem
    if verbose
      puts "Out: #{File.read outfile.path}"
      puts "Err: #{File.read errfile.path}"
    end
  else
    # Error out
    puts "Command failed, error output:"
    puts File.exist?(errfile.path) ? File.read(errfile.path) : "(No file created)"
    raise "Command #{cmd.inspect} failed!"
  end

  yield(File.read(outfile.path), File.read(errfile.path))
ensure
  outfile.unlink
  errfile.unlink
end

if File.exist?(RHTTP_REPO)
  Dir.chdir(RHTTP_REPO) do
    system "git fetch && git checkout main && git pull" || raise("Error git pulling in repo: #{$!.inspect}")
  end
else
  system "git clone https://github.com/noahgibbs/rebuilding_http.git #{RHTTP_REPO}" || raise("Couldn't clone repo! #{$!.inspect}")
end

# Helper Methods
class Minitest::Test
  def check_out_git_tag(tag)
    Dir.chdir(RHTTP_REPO) do
      system "git checkout #{tag}" || raise("Error checking out git tag #{tag}: #{$!.inspect}")
    end
  end

  # Returns the server PID
  def time_limited_fork_server(t: 5.0, cmd:, dir: RHTTP_REPO)
    pid = fork do
      STDOUT.reopen("/dev/null", "w")
      STDERR.reopen("/dev/null", "w")

      # Replace this process with little_app
      Dir.chdir dir  # Make sure current directory is what we expect
      exec cmd

      exit!(0)
    end
    Thread.new do
      sleep t
      Process.kill 9, pid
    end
    sleep 0.5 # Let the server start up
    pid
  end
end

class TestChapterOneCode < Minitest::Test
  def setup
    check_out_git_tag("chapter_2")
    @server_pid = time_limited_fork_server(cmd: "ruby my_server.rb", dir: RHTTP_REPO)
  end
  def teardown
    Process.kill(9, @server_pid) if @server_pid
  end

  def test_expected_out
    with_cmd_out_and_err(cmd: "curl -v http://localhost:4321") do |out, _err|
      assert out.include?("Hello World"), "Server output #{out.inspect} must include 'Hello World'!"
    end
  end
end

class TestChapterTwoCode < Minitest::Test
  def setup
    check_out_git_tag("chapter_3")
    @server_pid = time_limited_fork_server(cmd: "ruby my_server.rb", dir: RHTTP_REPO)
  end
  def teardown
    Process.kill(9, @server_pid) if @server_pid
  end

  def test_expected_out
    with_cmd_out_and_err(cmd: "curl -v http://localhost:4321") do |out, _err|
      assert out.include?("Hello From a Library, World"), "Server output #{out.inspect} must include 'Hello From a Library World'!"
    end
  end
end

class TestChapterThreeCode < Minitest::Test
  def setup
    check_out_git_tag("chapter_4")
    @server_pid = time_limited_fork_server(cmd: "ruby my_server.rb", dir: RHTTP_REPO)
  end
  def teardown
    Process.kill(9, @server_pid) if @server_pid
  end

  def test_expected_out
    with_cmd_out_and_err(cmd: "curl -v http://localhost:4321") do |out, err|
      assert out.include?("Hello Response"), "Server output #{out.inspect} must include 'Hello Response'!"
      assert err.include?("Framework: UltraCool")
    end
  end
end
