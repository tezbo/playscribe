# Cheap guard for the lanes, run before every TestFlight job (`bundle exec ruby fastlane/check_api.rb` in ios/).
# A Fastfile that parses can still name a constant that is not loaded when a lane runs (Pilot, notes run 41901431426).
fastfile = File.read(File.join(__dir__, 'Fastfile'))
code = fastfile.lines.reject { |l| l.strip.start_with?('#') }.join
bad = code.scan(/\b(?:Pilot|Deliver|Snapshot|Gym|Scan)::\w+/).uniq
abort("Fastfile uses constants that are only loaded inside actions: #{bad.join(', ')}") unless bad.empty?

begin
  require 'fastlane'
rescue LoadError
  puts 'fastlane is not installed here; only the static check ran'
  exit 0
end

api = Spaceship::ConnectAPI
missing = []
missing << 'Spaceship::ConnectAPI::App.find' unless api::App.respond_to?(:find)
missing << 'Spaceship::ConnectAPI::Build.all' unless api::Build.respond_to?(:all)
missing << 'Build#get_beta_build_localizations' unless api::Build.method_defined?(:get_beta_build_localizations)
missing << 'App#get_beta_app_localizations' unless api::App.method_defined?(:get_beta_app_localizations)
%i[post_beta_build_localizations patch_beta_build_localizations].each do |m|
  missing << "Spaceship::ConnectAPI.#{m}" unless api.respond_to?(m)
end
%i[whats_new locale].each { |a| missing << "BetaBuildLocalization##{a}" unless api::BetaBuildLocalization.method_defined?(a) }
%i[processing_state version].each { |a| missing << "Build##{a}" unless api::Build.method_defined?(a) }
abort("Fastfile relies on missing fastlane API: #{missing.join(', ')}") unless missing.empty?
puts 'Fastfile API check passed'
