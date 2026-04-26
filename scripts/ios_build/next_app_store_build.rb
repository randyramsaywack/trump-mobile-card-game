#!/usr/bin/env ruby
# frozen_string_literal: true

require "base64"
require "json"
require "net/http"
require "openssl"
require "optparse"
require "uri"

ROOT = File.expand_path("../..", __dir__)
PROJECT_FILE = File.join(ROOT, "Trump.xcodeproj", "project.pbxproj")
API_BASE = "https://api.appstoreconnect.apple.com/v1"

options = {
  apply: false,
  allow_local_fallback: false,
  bundle_id: ENV.fetch("ASC_BUNDLE_ID", "com.randyland.trumpcardgame"),
  project_file: PROJECT_FILE
}

OptionParser.new do |opts|
  opts.banner = "Usage: next_app_store_build.rb [--apply] [--allow-local-fallback]"
  opts.on("--apply", "Write the next build number into the Xcode project") { options[:apply] = true }
  opts.on("--allow-local-fallback", "Use local CURRENT_PROJECT_VERSION when App Store Connect credentials are absent") do
    options[:allow_local_fallback] = true
  end
  opts.on("--bundle-id ID", "Bundle identifier (default: ASC_BUNDLE_ID or #{options[:bundle_id]})") do |value|
    options[:bundle_id] = value
  end
  opts.on("--project-file PATH", "Xcode project.pbxproj path") { |value| options[:project_file] = value }
end.parse!

def project_value(project_file, key)
  values = File.read(project_file).scan(/#{Regexp.escape(key)} = ([^;]+);/).flatten.map(&:strip).uniq
  abort "Could not find #{key} in #{project_file}" if values.empty?
  warn "Warning: multiple #{key} values found: #{values.join(", ")}; using #{values.first}" if values.size > 1
  values.first
end

def local_builds(project_file)
  File.read(project_file).scan(/CURRENT_PROJECT_VERSION = ([^;]+);/).flatten.map(&:strip)
end

def sortable_build(build)
  build.to_s.split(".").map { |part| part[/\d+/].to_i }
end

def max_build(builds)
  builds.compact.map(&:to_s).reject(&:empty?).max_by { |build| sortable_build(build) }
end

def next_build(build)
  value = build.to_s.strip
  return "1" if value.empty?
  if value.match?(/\A\d+\z/)
    (value.to_i + 1).to_s
  elsif value.match?(/\A\d+(?:\.\d+)*\z/)
    parts = value.split(".")
    parts[-1] = (parts[-1].to_i + 1).to_s
    parts.join(".")
  else
    abort "Cannot auto-increment non-numeric build number: #{value.inspect}"
  end
end

def base64url(data)
  Base64.urlsafe_encode64(data).delete("=")
end

def der_to_jose_signature(der)
  sequence = OpenSSL::ASN1.decode(der)
  r, s = sequence.value.map { |integer| integer.value.to_i.to_s(2).rjust(32, "\x00")[-32, 32] }
  r + s
end

def app_store_token
  key_id = ENV["ASC_KEY_ID"]
  issuer_id = ENV["ASC_ISSUER_ID"]
  key_path = ENV["ASC_PRIVATE_KEY_PATH"]
  key_pem = ENV["ASC_PRIVATE_KEY"]
  missing = []
  missing << "ASC_KEY_ID" if key_id.to_s.empty?
  missing << "ASC_ISSUER_ID" if issuer_id.to_s.empty?
  missing << "ASC_PRIVATE_KEY_PATH or ASC_PRIVATE_KEY" if key_path.to_s.empty? && key_pem.to_s.empty?
  return nil unless missing.empty?

  key_data = key_pem.to_s.empty? ? File.read(File.expand_path(key_path)) : key_pem.gsub("\\n", "\n")
  key = OpenSSL::PKey::EC.new(key_data)
  now = Time.now.to_i
  header = { alg: "ES256", kid: key_id, typ: "JWT" }
  payload = { iss: issuer_id, iat: now, exp: now + 20 * 60, aud: "appstoreconnect-v1" }
  signing_input = "#{base64url(header.to_json)}.#{base64url(payload.to_json)}"
  signature = der_to_jose_signature(key.dsa_sign_asn1(OpenSSL::Digest::SHA256.digest(signing_input)))
  "#{signing_input}.#{base64url(signature)}"
end

def get_json(path, token, params = {})
  uri = URI("#{API_BASE}#{path}")
  uri.query = URI.encode_www_form(params) unless params.empty?
  request = Net::HTTP::Get.new(uri)
  request["Authorization"] = "Bearer #{token}"
  response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(request) }
  unless response.is_a?(Net::HTTPSuccess)
    abort "App Store Connect request failed #{response.code}: #{response.body}"
  end
  JSON.parse(response.body)
end

def app_id_for_bundle_id(bundle_id, token)
  response = get_json("/apps", token, {
    "filter[bundleId]" => bundle_id,
    "fields[apps]" => "bundleId,name",
    "limit" => "1"
  })
  app = response.fetch("data", []).first
  abort "No App Store Connect app found for bundle id #{bundle_id}" if app.nil?
  app.fetch("id")
end

def remote_builds(app_id, marketing_version, token)
  builds = []
  path = "/builds"
  params = {
    "filter[app]" => app_id,
    "filter[preReleaseVersion.version]" => marketing_version,
    "fields[builds]" => "version",
    "limit" => "200"
  }

  loop do
    response = get_json(path, token, params)
    builds.concat(response.fetch("data", []).map { |build| build.fetch("attributes", {}).fetch("version", nil) })
    next_url = response.dig("links", "next")
    break if next_url.nil? || next_url.empty?

    uri = URI(next_url)
    path = uri.path.sub(%r{\A/v1}, "")
    params = URI.decode_www_form(uri.query || "").to_h
  end
  builds
end

def write_build_number(project_file, build_number)
  content = File.read(project_file)
  updated = content.gsub(/CURRENT_PROJECT_VERSION = [^;]+;/, "CURRENT_PROJECT_VERSION = #{build_number};")
  File.write(project_file, updated)
end

marketing_version = project_value(options[:project_file], "MARKETING_VERSION")
local_latest = max_build(local_builds(options[:project_file]))
token = app_store_token

remote_latest = nil
source = "local project"

if token
  app_id = app_id_for_bundle_id(options[:bundle_id], token)
  remote_latest = max_build(remote_builds(app_id, marketing_version, token))
  source = "App Store Connect"
elsif !options[:allow_local_fallback]
  abort <<~MSG
    App Store Connect credentials are not configured.
    Set ASC_KEY_ID, ASC_ISSUER_ID, and ASC_PRIVATE_KEY_PATH (or ASC_PRIVATE_KEY),
    or pass --allow-local-fallback to increment from the local project.
  MSG
end

latest = max_build([remote_latest, local_latest])
next_value = next_build(latest)

puts "Marketing version: #{marketing_version}"
puts "Bundle id: #{options[:bundle_id]}"
puts "Latest App Store Connect build: #{remote_latest || "none"}"
puts "Latest local build: #{local_latest || "none"}"
puts "Next build: #{next_value} (source: #{source})"

if options[:apply]
  write_build_number(options[:project_file], next_value)
  puts "Updated #{options[:project_file]}"
end
