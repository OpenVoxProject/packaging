require 'time'

Gem::Specification.new do |gem|
  gem.name    = 'packaging'
  gem.version = '1.0.0'

  gem.summary = "Puppet Labs' packaging automation"
  gem.description = 'Packaging automation written in Rake and Ruby. Easily build native packages for most platforms with a few data files and git.'
  gem.license = 'Apache-2.0'

  gem.authors  = ['Puppet Labs', 'OpenVoxProject']
  gem.email    = 'openvox@voxpupuli.org'
  gem.homepage = 'http://github.com/OpenVoxProject/packaging'

  gem.required_ruby_version = '>= 3.2.0'

  gem.add_development_dependency('rspec', ['>= 2.14.1', '< 4'])
  gem.add_development_dependency('voxpupuli-rubocop', '~> 5.1.0')
  gem.add_dependency('artifactory', ['~> 3'])
  gem.add_dependency('base64', ['< 0.4'])
  gem.add_dependency('benchmark', '< 0.6')
  gem.add_dependency('csv', ['~> 3.0'])
  gem.add_dependency('rake', ['>= 12.3'])
  gem.add_dependency('release-metrics')
  gem.require_path = 'lib'

  # Ensure the gem is built out of versioned files
  gem.files = Dir['{lib,spec,static_artifacts,tasks,templates}/**/*', 'README*', 'LICENSE*'] & `git ls-files -z`.split("\0")
end
