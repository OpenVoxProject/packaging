require 'time'

Gem::Specification.new do |gem|
  gem.name    = 'packaging'
  gem.version = `git describe --tags`.tr('-', '.').chomp

  gem.summary = "Puppet Labs' packaging automation"
  gem.description = 'Packaging automation written in Rake and Ruby. Easily build native packages for most platforms with a few data files and git.'
  gem.license = 'Apache-2.0'

  gem.authors  = ['Puppet Labs']
  gem.email    = 'info@puppetlabs.com'
  gem.homepage = 'http://github.com/puppetlabs/packaging'

  gem.required_ruby_version = '>= 3.2.0'

  gem.add_development_dependency('pry-byebug')
  gem.add_development_dependency('rspec', ['>= 2.14.1', '< 4'])
  gem.add_development_dependency('voxpupuli-rubocop', ['~> 4.1.0'])
  gem.add_dependency('artifactory', ['~> 3'])
  gem.add_dependency('base64', ['< 0.4'])
  gem.add_dependency('benchmark', ['< 0.5'])
  gem.add_dependency('csv', ['3.1.5'])
  gem.add_dependency('rake', ['>= 12.3'])
  gem.add_dependency('release-metrics')
  gem.require_path = 'lib'

  # Ensure the gem is built out of versioned files
  gem.files = Dir['{lib,spec,static_artifacts,tasks,templates}/**/*', 'README*', 'LICENSE*'] & `git ls-files -z`.split("\0")
end
