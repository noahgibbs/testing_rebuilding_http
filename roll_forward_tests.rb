#!/usr/bin/env ruby -w

if RUBY_VERSION[0] != "3"
  raise "Please use Ruby version 3! (because Noah installs his gems there, not because this uses fancy features)"
end

require "socket"
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
    system "git fetch && git checkout main && git reset --hard origin/main && git pull -f --tags" || raise("Error git pulling in repo: #{$!.inspect}")
  end
else
  system "git clone https://github.com/noahgibbs/rebuilding_http.git #{RHTTP_REPO}" || raise("Couldn't clone repo! #{$!.inspect}")
end

# Helper Methods
class Minitest::Test
  def check_out_git_tag(tag)
    Dir.chdir(RHTTP_REPO) do
      with_cmd_out_and_err(cmd: "git checkout #{tag}") { }
      #system "git checkout #{tag}" || raise("Error checking out git tag #{tag}: #{$!.inspect}")
    end
  end

  # Returns the server PID
  def time_limited_fork_server(t: 5.0, cmd:, dir: RHTTP_REPO, server_sleep: 0.5)
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
    sleep server_sleep if server_sleep > 0.0 # Let the server start up
    pid
  end

  def with_time_limited_fork_server(t: 5.0, cmd:, dir: RHTTP_REPO)
    pid = time_limited_fork_server(t: t, cmd: cmd, dir: dir)
    yield
    Process.kill 9, pid
  end

  def with_open_connections(how_many:1, port:4321)
    # Open plausible-looking but incomplete connections
    conns = (0...how_many).map { s = TCPSocket.new('localhost', port); s.write "GET / HTTP/1.1\r\nHost:"; s }
    yield
    conns.each { |s| s.close }
  end

  def bad_http_request(how_many:1, port:4321)
    # Send a malformed HTTP request
    (0...how_many).each do
      s = TCPSocket.new('localhost', port)
      s.write "GET / asdfnjk;sdnfgdjsknflnsdaljkndjksanfjklsad\r\nHost: bad-host.com"
      s.close
    end
  end

  def assert_string_includes(str, inc, times: 1)
    if times == 1
      assert str.include?(inc), "Expected string #{str.inspect} to include #{inc.inspect}!"
    else
      assert str.scan(Regexp.new(inc)).size >= times, "Expected string #{str.inspect} to include #{inc.inspect} #{times} times!"
    end
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

  # By making sure each test has a unique name, you can run them individually with the Minitest --name parameter
  def test_expected_out_chapter_1
    with_cmd_out_and_err(cmd: "curl -v http://localhost:4321") do |out, _err|
      assert_string_includes(out, "Hello World")
    end

    # Test multiple consecutive requests on the same connection
    with_cmd_out_and_err(cmd: "curl http://localhost:4321 http://localhost:4321 http://localhost:4321") do |out, _err|
      assert_string_includes out, "Hello World!", times: 3
    end
  end

  def test_bad_requests_chapter_1
    bad_http_request(how_many: 1, port:4321)
    with_cmd_out_and_err(cmd: "curl http://localhost:4321") do |out, _err|
      assert_string_includes(out, "Hello World")
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

  def test_expected_out_chapter_2
    with_cmd_out_and_err(cmd: "curl -v http://localhost:4321") do |out, _err|
      assert_string_includes out, "Hello From a Library, World"
    end
    with_cmd_out_and_err(cmd: "curl http://localhost:4321 http://localhost:4321 http://localhost:4321") do |out, _err|
      assert_string_includes out, "Hello From a Library, World", times: 3
    end
  end

  # Don't expect this to work for the chapter 2 server, no error handling
  #def test_bad_requests
  #  bad_http_request(how_many: 1, port:4321)
  #  with_cmd_out_and_err(cmd: "curl http://localhost:4321") do |out, _err|
  #    assert_string_includes(out, "Hello World")
  #  end
  #end
end

class TestChapterThreeCode < Minitest::Test
  def setup
    check_out_git_tag("chapter_4")
    @server_pid = time_limited_fork_server(cmd: "ruby my_server.rb", dir: RHTTP_REPO)
  end
  def teardown
    Process.kill(9, @server_pid) if @server_pid
  end

  def test_expected_out_chapter_3
    with_cmd_out_and_err(cmd: "curl -v http://localhost:4321") do |out, err|
      assert_string_includes out, "Hello Response"
      assert_string_includes err, "Framework: UltraCool"
    end
    with_cmd_out_and_err(cmd: "curl http://localhost:4321 http://localhost:4321 http://localhost:4321") do |out, _err|
      assert_string_includes out, "Hello Response", times: 3
    end
  end

  def test_bad_requests_chapter_3
    bad_http_request(how_many: 1, port:4321)
    with_cmd_out_and_err(cmd: "curl http://localhost:4321") do |out, _err|
      assert_string_includes(out, "Hello Response")
    end
  end
end

class TestChapterFourCode < Minitest::Test
  def setup
    check_out_git_tag("chapter_5")
    @server_pid = time_limited_fork_server(cmd: "ruby -I./lib -rblue_eyes/dsl little_app.rb", dir: File.join(RHTTP_REPO, "blue_eyes"))
  end
  def teardown
    Process.kill(9, @server_pid) if @server_pid
  end

  def test_expected_out_chapter_4
    with_cmd_out_and_err(cmd: "curl http://localhost:4321/frank") do |out, _err|
      assert_string_includes out, "I did it my way..."
    end
    with_cmd_out_and_err(cmd: "curl http://localhost:4321") do |out, _err|
      assert_string_includes out, "Who are you looking for?"
    end
    with_cmd_out_and_err(cmd: "curl http://localhost:4321 http://localhost:4321 http://localhost:4321") do |out, _err|
      assert_string_includes out, "Who are you looking for?", times: 3
    end
  end

  def test_bad_requests_chapter_4
    bad_http_request(how_many: 1, port:4321)
    with_cmd_out_and_err(cmd: "curl http://localhost:4321") do |out, _err|
      assert_string_includes(out, "Who are you looking for?")
    end
  end
end

class TestChapterFiveCode < Minitest::Test
  def setup
    check_out_git_tag("chapter_6")
    @server_pid = time_limited_fork_server(cmd: "ruby -I./lib -rblue_eyes/dsl little_form.rb", dir: File.join(RHTTP_REPO, "blue_eyes"))
  end
  def teardown
    Process.kill(9, @server_pid) if @server_pid
  end

  def test_expected_out_chapter_5
    with_cmd_out_and_err(cmd: "curl http://localhost:4321/") do |out, _err|
      assert_string_includes out, "Who are you?"
    end
    with_cmd_out_and_err(cmd: "curl -d who=Bobo http://localhost:4321/") do |out, _err|
      assert_string_includes out, "Hello, Bobo"
      assert_string_includes out, "Request headers"
    end
    # Test multiple consecutive requests on the same connection
    with_cmd_out_and_err(cmd: "curl -d who=Bobo http://localhost:4321 http://localhost:4321 http://localhost:4321") do |out, _err|
      assert_string_includes out, "Hello, Bobo", times: 3
    end
    with_cmd_out_and_err(cmd: "curl -d who=one%2bone http://localhost:4321/") do |out, _err|
      assert_string_includes out, "Hello, one+one"
    end
  end

  def test_bad_requests_chapter_5
    bad_http_request(how_many: 1, port:4321)
    with_cmd_out_and_err(cmd: "curl http://localhost:4321") do |out, _err|
      assert_string_includes(out, "Who are you?")
    end
  end
end

# Misbehaviour chapter (thread pool)
class TestChapterSixCode < Minitest::Test
  def setup
    check_out_git_tag("chapter_7")
    @server_pid = time_limited_fork_server(cmd: "ruby -I./lib -rblue_eyes/dsl little_form.rb", dir: File.join(RHTTP_REPO, "blue_eyes"))
  end
  def teardown
    Process.kill(9, @server_pid) if @server_pid
  end

  def test_expected_out_chapter_6
    with_cmd_out_and_err(cmd: "curl http://localhost:4321/") do |out, _err|
      assert_string_includes out, "Who are you?"
    end

    with_cmd_out_and_err(cmd: "curl http://localhost:4321/ http://localhost:4321/ http://localhost:4321/") do |out, _err|
      assert_string_includes out, "Who are you?", times: 3
    end
  end

  def test_for_request_headers_chapter_6
    with_cmd_out_and_err(cmd: "curl -d who=Bobo http://localhost:4321/") do |out, _err|
      assert_string_includes out, "Hello, Bobo"
      assert_string_includes out, "Request headers"
    end
  end

  def test_misbehaviour
    with_open_connections(how_many: 8) do
      with_cmd_out_and_err(cmd: "curl http://localhost:4321/") do |out, _err|
        assert_string_includes out, "Who are you?"
      end
    end
  end

  def test_bad_requests_chapter_6
    bad_http_request(how_many: 1, port:4321)
    with_cmd_out_and_err(cmd: "curl http://localhost:4321") do |out, _err|
      assert_string_includes(out, "Who are you?")
    end
  end
end

# The Rack chapter
class TestChapterSevenCode < Minitest::Test
  def setup
    check_out_git_tag("chapter_8")
    @server_pid = time_limited_fork_server(cmd: "bundle exec ruby sin_app.rb", dir: RHTTP_REPO, server_sleep: 1.0)
  end
  def teardown
    Process.kill(9, @server_pid) if @server_pid
  end

  def test_expected_out_chapter_7
    with_cmd_out_and_err(cmd: "curl http://localhost:4567/") do |out, _err|
      assert_string_includes out, "Here I am!"
    end

    with_cmd_out_and_err(cmd: "curl http://localhost:4567/ http://localhost:4567/ http://localhost:4567/") do |out, _err|
      assert_string_includes out, "Here I am!", times: 3
    end
  end

  def test_bad_requests_chapter_7
    bad_http_request(how_many: 1, port:4567)
    with_cmd_out_and_err(cmd: "curl http://localhost:4567") do |out, _err|
      assert_string_includes(out, "Here I am!")
    end
  end
end
