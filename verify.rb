require "bundler"
require "digest"
require "json"
require "pathname"
require "rack/version"

mode, stage = ARGV
raise "Unexpected engine: #{RUBY_ENGINE}" unless RUBY_ENGINE == "ruby"
raise "Expected Bundler 4.1" unless Bundler::VERSION == "4.1.0"
archives = Dir.glob("vendor/bundle/**/cache/*.gem").sort
if mode == "default"
  raise "retained downloaded gems: #{archives}" unless archives.empty?
  require "webrick"
  require "rack/mock"
  raise "Rack probe failed" unless Rack::MockRequest.new(->(env) { [200, {"content-type" => "text/plain"}, ["rack-ok"]] }).get("/").body == "rack-ok"
  selected = Gem.loaded_specs.fetch("webrick")
else
  require "rack/mock"
  response = Rack::MockRequest.new(->(env) { [201, {"content-type" => "text/plain"}, ["cached"]] }).post("/native")
  raise "Rack probe failed" unless response.status == 201 && response.body == "cached"
  raise "missing .gem after opt-out" unless archives.any? { |n| File.basename(n) == "rack-3.2.4.gem" }
  selected = Gem.loaded_specs.fetch("rack")
end
files = Dir.glob(File.join(selected.full_gem_path, "lib", "**", "*.rb")).sort
raise "no installed Ruby sources" if files.empty?
digest = Digest::SHA256.new
files.each do |path|
  digest.update(Pathname.new(path).relative_path_from(Pathname.new(selected.full_gem_path)).to_s.tr("\\", "/"))
  digest.update(Digest::SHA256.file(path).digest)
end
result={stage: stage, mode: mode, ruby: RUBY_DESCRIPTION, bundler: Bundler::VERSION, os: RUBY_PLATFORM, lock_sha256: Digest::SHA256.file("Gemfile.lock").hexdigest, downloads: archives.map { |n| File.basename(n) }, gem: selected.full_name, gem_source_files: files.length, gem_source_sha256: digest.hexdigest, rack: Rack.release}
puts "RUBY_983_CACHE=" + JSON.generate(result)
