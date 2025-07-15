begin
  require 'voxpupuli/rubocop/rake'
rescue LoadError
  # the voxpupuli-rubocop gem is optional
end

begin
  require 'github_changelog_generator/task'
rescue LoadError
  # gem is missing
else
  GitHubChangelogGenerator::RakeTask.new :changelog do |config|
    config.header = "# Changelog\n\nAll notable changes to this project will be documented in this file."
    config.exclude_labels = %w[duplicate question invalid wontfix wont-fix modulesync skip-changelog github_actions]
    config.user = 'OpenVoxProject'
    config.project = 'packaging'
    config.future_release = Gem::Specification.load("#{config.project}.gemspec").version
    config.since_tag = '0.99.76' # last release from Perforce
    config.exclude_tags_regex = /\A0\.\d\d\d/
    config.release_branch = 'main'
  end

  # Workaround for https://github.com/github-changelog-generator/github-changelog-generator/issues/715
  require 'rbconfig'
  if RbConfig::CONFIG['host_os'].include?('linux')
    task :changelog do
      puts 'Fixing line endings...'
      changelog_file = File.join(__dir__, 'CHANGELOG.md')
      changelog_txt = File.read(changelog_file)
      new_contents = changelog_txt.gsub("\r\n", "\n")
      File.open(changelog_file, 'w') { |file| file.puts new_contents }
    end
  end
end
