namespace :config do
  desc "print Pkg::Config values for this repo"
  task :print => 'pl:fetch' do
    Pkg::Util.filter_configs.each do |key, value|
      puts "#{key}: #{value}"
    end
  end

  desc "validate Pkg::Config values for this repo"
  task :validate do
    Pkg::Config.perform_validations
  end

  task :print_hosts => 'pl:fetch' do
    Pkg::Util.filter_configs('host').each do |key, value|
      puts "#{key}: #{value}"
    end
  end

  desc "print environment variables that can override build-data and build_defaults"
  task :environment_variables do
    Pkg::Params::ENV_VARS.each do |values|
      type = case values[:type]
      when :array
        "expects one or more space, comma, or semicolon delimited value; treated as an array"
      when :bool
        "expects a boolean value"
             end

      msg = "#{values[:var]}: #{values[:envvar]}"
      msg += " (#{type})" if type
      puts msg
    end
  end
end
