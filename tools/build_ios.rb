#!/usr/bin/env ruby
# Local iOS configuration/build entry point. Default mode is read-only.
require 'base64'
require 'json'
require 'open3'
require 'openssl'
require 'tempfile'

module IOSBuild
  ROOT = File.expand_path('..', __dir__)
  EXPECTED_CA_SHA256 = 'A8FD32298C18E9C43AC7AD00D8F5F6D32335C42696CFA682C8C5B81A3517C24F'
  ENV_KEYS = %w[APP_BACKEND_KEY API_BASE API_CERT_SHA256].freeze
  class InputError < StandardError; end

  def self.properties(path)
    raise InputError, 'Missing .secrets/prod.env.' unless File.file?(path)
    result = {}
    File.foreach(path, encoding: 'bom|utf-8') do |line|
      text = line.strip
      next if text.empty? || text.start_with?('#', '!')
      key, value = text.split('=', 2)
      next unless value && ENV_KEYS.include?(key.strip.upcase)
      result[key.strip.upcase] = value.strip
    end
    result
  end

  def self.inputs(root)
    props = properties(File.join(root, '.secrets/prod.env'))
    key = props['APP_BACKEND_KEY'].to_s
    raise InputError, 'APP_BACKEND_KEY is missing or contains whitespace.' if key.empty? || key.match?(/\s/)
    base = props['API_BASE'].to_s
    unless base.match?(%r{\Ahttps://[^\s/@?#]+/?\z})
      raise InputError, 'API_BASE must be an HTTPS origin without credentials, path or query.'
    end
    pin = props['API_CERT_SHA256'].to_s.delete(':').downcase
    unless pin.empty? || pin.match?(/\A[0-9a-f]{64}\z/)
      raise InputError, 'API_CERT_SHA256 must be a SHA-256 certificate fingerprint.'
    end
    # The Windows API_CA_FILE points to a sibling backend checkout.
    # iOS deliberately uses the separately verified local public CA copy.
    ca_path = File.join(root, '.secrets/ca.crt')
    raise InputError, 'Missing .secrets/ca.crt.' unless File.file?(ca_path)
    pem = File.binread(ca_path)
    raise InputError, 'CA file contains private-key material; stopped.' if pem.include?('PRIVATE KEY')
    blocks = pem.scan(/-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----/m)
    raise InputError, 'Expected exactly one PEM public CA certificate.' unless blocks.length == 1
    cert = OpenSSL::X509::Certificate.new(blocks.first)
    fingerprint = OpenSSL::Digest::SHA256.hexdigest(cert.to_der).upcase
    unless fingerprint == EXPECTED_CA_SHA256
      raise InputError, 'CA differs from the verified Windows/Android source; stopped.'
    end
    unless cert.extensions.any? { |e| e.oid == 'basicConstraints' && e.value.include?('CA:TRUE') }
      raise InputError, 'Certificate is not a CA.'
    end
    unless cert.not_before <= Time.now && Time.now < cert.not_after
      raise InputError, 'CA certificate is not currently valid.'
    end
    [props, pem, fingerprint]
  end

  def self.configured_keys(root)
    result = {}
    path = File.join(root, 'ios/Flutter/Generated.xcconfig')
    return result unless File.file?(path)
    File.foreach(path) do |line|
      next unless line.start_with?('DART_DEFINES=')
      line.split('=', 2)[1].strip.split(',').each do |encoded|
        key, value = Base64.strict_decode64(encoded).split('=', 2)
        result[key] = value
      end
    end
    result
  end

  def self.flutter_path
    candidates = ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).map { |p| File.join(p, 'flutter') }
    candidates << File.expand_path('~/development/flutter/bin/flutter')
    candidates.find { |p| File.file?(p) && File.executable?(p) } ||
      raise(InputError, 'Flutter executable not found.')
  end

  def self.run(mode, root = ROOT)
    unless %w[--check --configure --build].include?(mode)
      raise InputError, 'Usage: ruby tools/build_ios.rb [--check|--configure|--build]'
    end
    raise InputError, 'Run on the Mac with the iOS project.' unless RUBY_PLATFORM.include?('darwin')
    raise InputError, 'iOS project is missing.' unless File.file?(File.join(root, 'ios/Runner.xcodeproj/project.pbxproj'))
    props, pem, fingerprint = inputs(root)
    configured = configured_keys(root)
    puts JSON.generate({
      'prod_env_ready' => true,
      'ca_matches_windows_android' => true,
      'ca_sha256' => fingerprint,
      'build_key_configured' => !configured['APP_BACKEND_KEY'].to_s.empty?,
      'build_api_base_configured' => !configured['API_BASE'].to_s.empty?,
      'build_ca_configured' => !configured['API_CA_PEM_B64'].to_s.empty?
    })
    return if mode == '--check'

    # These modes intentionally put the existing production credential into
    # generated local build files. Do not run before the requested confirmation.
    flutter = flutter_path
    defines = {
      'APP_BACKEND_KEY' => props.fetch('APP_BACKEND_KEY'),
      'API_BASE' => props.fetch('API_BASE').sub(%r{/\z}, ''),
      'API_CA_PEM_B64' => Base64.strict_encode64(pem)
    }
    pin = props['API_CERT_SHA256'].to_s.delete(':').downcase
    defines['API_CERT_SHA256'] = pin unless pin.empty?
    hash, status = Open3.capture2('git', 'rev-parse', '--short', 'HEAD', chdir: root)
    raise InputError, 'Cannot determine the source revision.' unless status.success?
    dirty, status = Open3.capture2('git', 'status', '--porcelain', chdir: root)
    raise InputError, 'Cannot determine the working-tree state.' unless status.success?
    defines['APP_BUILD'] = hash.strip + (dirty.empty? ? '' : '-dirty')

    args = [flutter, 'build', 'ios', '--debug', '--no-codesign', '--no-pub']
    args << '--config-only' if mode == '--configure'
    puts(mode == '--configure' ? 'Updating local Xcode build configuration...' : 'Building unsigned iOS app locally...')
    success = false
    Tempfile.create(['ios-prod-', '.json'], File.join(root, '.secrets')) do |file|
      file.chmod(0600)
      file.write(JSON.generate(defines))
      file.flush
      # Capture output in memory. Flutter/Xcode errors can echo build defines;
      # do not print or persist the raw subprocess output.
      _stdout, _stderr, result = Open3.capture3(*args, "--dart-define-from-file=#{file.path}", chdir: root)
      success = result.success?
    end
    raise InputError, 'Flutter failed; raw output was withheld because it may contain build credentials.' unless success
    current = configured_keys(root)
    unless defines.all? { |key, value| current[key] == value }
      raise InputError, 'Generated Xcode configuration does not match the requested inputs.'
    end
    if mode == '--build' && !File.directory?(File.join(root, 'build/ios/iphoneos/Runner.app'))
      raise InputError, 'Unsigned app output was not found.'
    end
    puts(mode == '--configure' ? 'Configuration verified. Xcode Run can now build with these inputs.' : 'Unsigned build passed. No app was installed or published.')
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    raise IOSBuild::InputError, 'Pass exactly one mode at most.' if ARGV.length > 1
    IOSBuild.run(ARGV.first || '--check')
  rescue IOSBuild::InputError => e
    warn e.message
    exit 1
  rescue StandardError => e
    warn "Local iOS preparation failed (#{e.class}); no secret values are shown."
    exit 1
  end
end
