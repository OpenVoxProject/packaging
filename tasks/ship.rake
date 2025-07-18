namespace :pl do
  namespace :remote do
    # These hacky bits execute a pre-existing rake task on the Pkg::Config.apt_host
    # The rake task takes packages in a specific directory and freights them
    # to various target yum and apt repositories based on their specific type
    # e.g., final vs devel vs PE vs FOSS packages

    desc "Update '#{Pkg::Config.repo_name}' yum repository on '#{Pkg::Config.yum_staging_server}'"
    task update_yum_repo: 'pl:fetch' do
      command = Pkg::Config.yum_repo_command || 'rake -f /opt/repository/Rakefile mk_repo'
      $stdout.puts "Really run remote repo update on '#{Pkg::Config.yum_staging_server}'? [y,n]"
      if Pkg::Util.ask_yes_or_no
        Pkg::Repo.update_repo(Pkg::Config.yum_staging_server, command, { :repo_name => Pkg::Paths.yum_repo_name, :repo_path => Pkg::Config.yum_repo_path, :repo_host => Pkg::Config.yum_staging_server })
      end
    end

    desc "Update all final yum repositories on '#{Pkg::Config.yum_staging_server}'"
    task update_all_final_yum_repos: 'pl:fetch' do
      command = Pkg::Config.yum_repo_command || 'rake -f /opt/repository/Rakefile mk_repo'
      $stdout.puts "Really run remote repo update on '#{Pkg::Config.yum_staging_server}'? [y,n]"
      if Pkg::Util.ask_yes_or_no
        Pkg::Repo.update_repo(Pkg::Config.yum_staging_server, command, { :repo_name => '', :repo_path => Pkg::Config.yum_repo_path, :repo_host => Pkg::Config.yum_staging_server })
      end
    end

    desc "Update '#{Pkg::Config.nonfinal_repo_name}' nightly yum repository on '#{Pkg::Config.yum_staging_server}'"
    task update_nightlies_yum_repo: 'pl:fetch' do
      command = Pkg::Config.yum_repo_command || 'rake -f /opt/repository-nightlies/Rakefile mk_repo'
      $stdout.puts "Really run remote repo update on '#{Pkg::Config.yum_staging_server}'? [y,n]"
      if Pkg::Util.ask_yes_or_no
        Pkg::Repo.update_repo(Pkg::Config.yum_staging_server, command, { :repo_name => Pkg::Config.nonfinal_repo_name, :repo_path => Pkg::Config.nonfinal_yum_repo_path, :repo_host => Pkg::Config.yum_staging_server })
      end
    end

    desc "Update all nightly yum repositories on '#{Pkg::Config.yum_staging_server}'"
    task update_all_nightlies_yum_repos: 'pl:fetch' do
      command = Pkg::Config.yum_repo_command || 'rake -f /opt/repository-nightlies/Rakefile mk_repo'
      $stdout.puts "Really run remote repo update on '#{Pkg::Config.yum_staging_server}'? [y,n]"
      if Pkg::Util.ask_yes_or_no
        Pkg::Repo.update_repo(Pkg::Config.yum_staging_server, command, { :repo_name => '', :repo_path => Pkg::Config.nonfinal_yum_repo_path, :repo_host => Pkg::Config.yum_staging_server })
      end
    end

    task freight: :update_apt_repo

    desc "Update remote apt repository on '#{Pkg::Config.apt_signing_server}'"
    task update_apt_repo: 'pl:fetch' do
      $stdout.puts "Really run remote repo update on '#{Pkg::Config.apt_signing_server}'? [y,n]"
      if Pkg::Util.ask_yes_or_no
        Pkg::Repo.update_repo(Pkg::Config.apt_signing_server, Pkg::Config.apt_repo_command, { :repo_name => Pkg::Paths.apt_repo_name, :repo_path => Pkg::Config.apt_repo_path, :repo_host => Pkg::Config.apt_host, :repo_url => Pkg::Config.apt_repo_url })
      end
    end

    desc "Update nightlies apt repository on '#{Pkg::Config.apt_signing_server}'"
    task update_nightlies_apt_repo: 'pl:fetch' do
      $stdout.puts "Really run remote repo update on '#{Pkg::Config.apt_signing_server}'? [y,n]"
      if Pkg::Util.ask_yes_or_no
        Pkg::Repo.update_repo(Pkg::Config.apt_signing_server, Pkg::Config.nonfinal_apt_repo_command, { :repo_name => Pkg::Config.nonfinal_repo_name, :repo_path => Pkg::Config.nonfinal_apt_repo_path, :repo_host => Pkg::Config.apt_host, :repo_url => Pkg::Config.apt_repo_url })
      end
    end

    desc "Update apt and yum repos"
    task :update_foss_repos => "pl:fetch" do
      Rake::Task['pl:remote:update_apt_repo'].invoke
      Rake::Task['pl:remote:update_yum_repo'].invoke
    end

    desc "Update nightlies apt and yum repos"
    task :update_nightly_repos => "pl:fetch" do
      Rake::Task['pl:remote:update_nightlies_apt_repo'].invoke
      Rake::Task['pl:remote:update_nightlies_yum_repo'].invoke
    end

    desc "Update remote ips repository on #{Pkg::Config.ips_host}"
    task :update_ips_repo => 'pl:fetch' do
      if Dir['pkg/ips/pkgs/**/*'].empty? && Dir['pkg/solaris/11/**/*'].empty?
        $stdout.puts "There aren't any p5p packages in pkg/ips/pkgs or pkg/solaris/11. Maybe something went wrong?"
      else

        if !Dir['pkg/ips/pkgs/**/*'].empty?
          source_dir = 'pkg/ips/pkgs/'
        else
          source_dir = 'pkg/solaris/11/'
        end

        tmpdir, = Pkg::Util::Net.remote_execute(
          Pkg::Config.ips_host,
          'mktemp -d -p /var/tmp',
          { capture_output: true },
        )
        tmpdir.chomp!

        Pkg::Util::Net.rsync_to(source_dir, Pkg::Config.ips_host, tmpdir)

        remote_cmd = %(for pkg in #{tmpdir}/*.p5p; do
      sudo pkgrecv -s $pkg -d #{Pkg::Config.ips_path} '*';
      done)

        Pkg::Util::Net.remote_execute(Pkg::Config.ips_host, remote_cmd)
        Pkg::Util::Net.remote_execute(Pkg::Config.ips_host, "sudo pkgrepo refresh -s #{Pkg::Config.ips_path}")
        Pkg::Util::Net.remote_execute(Pkg::Config.ips_host, "sudo /usr/sbin/svcadm restart svc:/application/pkg/server:#{Pkg::Config.ips_repo || 'default'}")
      end
    end

    desc "Move dmg repos from #{Pkg::Config.dmg_staging_server} to #{Pkg::Config.dmg_host}"
    task deploy_dmg_repo: 'pl:fetch' do
      puts "Really run remote rsync to deploy OS X repos from #{Pkg::Config.dmg_staging_server} to #{Pkg::Config.dmg_host}? [y,n]"
      if Pkg::Util.ask_yes_or_no
        Pkg::Util::Execution.retry_on_fail(times: 3) do
          cmd = Pkg::Util::Net.rsync_cmd(Pkg::Config.dmg_path, target_host: Pkg::Config.dmg_host, extra_flags: ['--update'])
          Pkg::Util::Net.remote_execute(Pkg::Config.dmg_staging_server, cmd)
        end
      end
    end

    desc "Move swix repos from #{Pkg::Config.swix_staging_server} to #{Pkg::Config.swix_host}"
    task deploy_swix_repo: 'pl:fetch' do
      puts "Really run remote rsync to deploy Arista repos from #{Pkg::Config.swix_staging_server} to #{Pkg::Config.swix_host}? [y,n]"
      if Pkg::Util.ask_yes_or_no
        Pkg::Util::Execution.retry_on_fail(times: 3) do
          cmd = Pkg::Util::Net.rsync_cmd(Pkg::Config.swix_path, target_host: Pkg::Config.swix_host, extra_flags: ['--update'])
          Pkg::Util::Net.remote_execute(Pkg::Config.swix_staging_server, cmd)
        end
      end
    end

    desc "Move tar repos from #{Pkg::Config.tar_staging_server} to #{Pkg::Config.tar_host}"
    task deploy_tar_repo: 'pl:fetch' do
      puts "Really run remote rsync to deploy source tarballs from #{Pkg::Config.tar_staging_server} to #{Pkg::Config.tar_host}? [y,n]"
      if Pkg::Util.ask_yes_or_no
        files = Dir.glob("pkg/#{Pkg::Config.project}-#{Pkg::Config.version}.tar.gz*")
        if files.empty?
          puts 'There are no tarballs to ship'
        else
          Pkg::Util::Execution.retry_on_fail(times: 3) do
            cmd = Pkg::Util::Net.rsync_cmd(Pkg::Config.tarball_path, target_host: Pkg::Config.tar_host, extra_flags: ['--update'])
            Pkg::Util::Net.remote_execute(Pkg::Config.tar_staging_server, cmd)
          end
        end
      end
    end

    desc "Move MSI repos from #{Pkg::Config.msi_staging_server} to #{Pkg::Config.msi_host}"
    task deploy_msi_repo: 'pl:fetch' do
      puts "Really run remote rsync to deploy source MSIs from #{Pkg::Config.msi_staging_server} to #{Pkg::Config.msi_host}? [y,n]"
      if Pkg::Util.ask_yes_or_no
        files = Dir.glob('pkg/windows/**/*.msi')
        if files.empty?
          puts 'There are no MSIs to ship'
        else
          Pkg::Util::Execution.retry_on_fail(times: 3) do
            cmd = Pkg::Util::Net.rsync_cmd(Pkg::Config.msi_path, target_host: Pkg::Config.msi_host, extra_flags: ['--update'])
            Pkg::Util::Net.remote_execute(Pkg::Config.msi_staging_server, cmd)
          end
        end
      end
    end

    desc "Move signed deb repos from #{Pkg::Config.apt_signing_server} to #{Pkg::Config.apt_host}"
    task deploy_apt_repo: 'pl:fetch' do
      puts "Really run remote rsync to deploy Debian repos from #{Pkg::Config.apt_signing_server} to #{Pkg::Config.apt_host}? [y,n]"
      if Pkg::Util.ask_yes_or_no
        Pkg::Util::Execution.retry_on_fail(times: 3) do
          Pkg::Deb::Repo.deploy_repos(
            Pkg::Config.apt_repo_path,
            Pkg::Config.apt_repo_staging_path,
            Pkg::Config.apt_signing_server,
            Pkg::Config.apt_host,
            ENV['DRYRUN'],
          )
        end
      end
    end

    desc "Copy signed deb repos from #{Pkg::Config.apt_signing_server} to AWS S3"
    task :deploy_apt_repo_to_s3 => 'pl:fetch' do
      puts "Really run S3 sync to deploy Debian repos from #{Pkg::Config.apt_signing_server} to AWS S3? [y,n]"
      if Pkg::Util.ask_yes_or_no
        Pkg::Util::Execution.retry_on_fail(:times => 3) do
          command = 'sudo /usr/local/bin/s3_repo_sync.sh apt.puppetlabs.com'
          Pkg::Util::Net.remote_execute(Pkg::Config.apt_signing_server, command)
        end
      end
    end

    desc "Copy rpm repos from #{Pkg::Config.yum_staging_server} to #{Pkg::Config.yum_host}"
    task deploy_yum_repo: 'pl:fetch' do
      puts "Really run remote rsync to deploy yum repos from #{Pkg::Config.yum_staging_server} to #{Pkg::Config.yum_host}? [y,n]"
      if Pkg::Util.ask_yes_or_no
        Pkg::Util::Execution.retry_on_fail(times: 3) do
          Pkg::Rpm::Repo.deploy_repos(
            Pkg::Config.yum_repo_path,
            Pkg::Config.yum_staging_server,
            Pkg::Config.yum_host,
            ENV['DRYRUN'],
          )
        end
      end
    end

    desc "Copy signed RPM repos from #{Pkg::Config.yum_staging_server} to AWS S3"
    task :deploy_yum_repo_to_s3 => 'pl:fetch' do
      puts "Really run S3 sync to deploy RPM repos from #{Pkg::Config.yum_staging_server} to AWS S3? [y,n]"
      if Pkg::Util.ask_yes_or_no
        Pkg::Util::Execution.retry_on_fail(:times => 3) do
          command = 'sudo /usr/local/bin/s3_repo_sync.sh yum.puppetlabs.com'
          Pkg::Util::Net.remote_execute(Pkg::Config.yum_staging_server, command)
        end
      end
    end

    desc "Sync downloads.puppetlabs.com from #{Pkg::Config.staging_server} to AWS S3"
    task :deploy_downloads_to_s3 => 'pl:fetch' do
      puts "Really run S3 sync to sync downloads.puppetlabs.com from #{Pkg::Config.staging_server} to AWS S3? [y,n]"
      if Pkg::Util.ask_yes_or_no
        Pkg::Util::Execution.retry_on_fail(:times => 3) do
          command = 'sudo /usr/local/bin/s3_repo_sync.sh downloads.puppetlabs.com'
          Pkg::Util::Net.remote_execute(Pkg::Config.staging_server, command)
        end
      end
    end

    desc "Sync apt, yum, and downloads.pl.com to AWS S3"
    task :deploy_final_builds_to_s3 => "pl:fetch" do
      Rake::Task['pl:remote:deploy_apt_repo_to_s3'].invoke
      Rake::Task['pl:remote:deploy_yum_repo_to_s3'].invoke
      Rake::Task['pl:remote:deploy_downloads_to_s3'].invoke
    end

    desc "Sync nightlies.puppetlabs.com from #{Pkg::Config.staging_server} to AWS S3"
    task :deploy_nightlies_to_s3 => 'pl:fetch' do
      puts "Deploying nightly builds from #{Pkg::Config.staging_server} to AWS S3..."
      Pkg::Util::Execution.retry_on_fail(:times => 3) do
        command = 'sudo /usr/local/bin/s3_repo_sync.sh nightlies.puppet.com'
        Pkg::Util::Net.remote_execute(Pkg::Config.staging_server, command)
      end
    end

    desc "Sync yum and apt from #{Pkg::Config.staging_server} to rsync servers"
    task :deploy_to_rsync_server => 'pl:fetch' do
      # This task must run after the S3 sync has run, or else /opt/repo-s3-stage won't be up-to-date
      puts "Really run rsync to sync apt and yum from #{Pkg::Config.staging_server} to rsync servers? Only say yes if the S3 sync task has run. [y,n]"
      if Pkg::Util.ask_yes_or_no
        Pkg::Util::Execution.retry_on_fail(:times => 3) do
          Pkg::Config.rsync_servers.each do |rsync_server|
            ['apt', 'yum'].each do |repo|
              # Don't --delete so that folks using archived packages can continue to do so
              command = "sudo su - rsync --command 'rsync --verbose -a --exclude '*.html' /opt/repo-s3-stage/repositories/#{repo}.puppetlabs.com/ rsync@#{rsync_server}:/opt/repository/#{repo}'"
              Pkg::Util::Net.remote_execute(Pkg::Config.staging_server, command)
            end
          end
        end
      end
    end

    desc "Remotely link nightly shipped gems to latest versions on #{Pkg::Config.gem_host}"
    task link_nightly_shipped_gems_to_latest: 'pl:fetch' do
      Pkg::Config.gemversion = Pkg::Util::Version.extended_dot_version

      remote_path = Pkg::Config.nonfinal_gem_path
      gems = FileList['pkg/*.gem'].map! { |path| path.gsub!('pkg/', '') }
      command = %(cd #{remote_path}; )

      command += gems.map! do |gem_name|
        %(sudo ln -sf #{gem_name} #{gem_name.gsub(Pkg::Config.gemversion, 'latest')})
      end.join(';')

      command += %(; sync)

      Pkg::Util::Net.remote_execute(Pkg::Config.gem_host, command)
    end
  end

  desc "Ship mocked rpms to #{Pkg::Config.yum_staging_server}"
  task ship_rpms: 'pl:fetch' do
    Pkg::Util::Ship.ship_rpms('pkg', Pkg::Config.yum_repo_path)
  end

  desc "Ship nightly rpms to #{Pkg::Config.yum_staging_server}"
  task ship_nightly_rpms: 'pl:fetch' do
    Pkg::Util::Ship.ship_rpms('pkg', Pkg::Config.nonfinal_yum_repo_path, nonfinal: true)
  end

  desc "Ship cow-built debs to #{Pkg::Config.apt_signing_server}"
  task ship_debs: 'pl:fetch' do
    Pkg::Util::Ship.ship_debs('pkg', Pkg::Config.apt_repo_staging_path, chattr: false)
  end

  desc "Ship nightly debs to #{Pkg::Config.apt_signing_server}"
  task ship_nightly_debs: 'pl:fetch' do
    Pkg::Util::Ship.ship_debs('pkg', Pkg::Config.nonfinal_apt_repo_staging_path, chattr: false, nonfinal: true)
  end

  desc 'Ship built gem to rubygems.org, internal Gem mirror, and public file server'
  task ship_gem: 'pl:fetch' do
    # We want to ship a Gem only for projects that build gems, so
    # all of the Gem shipping tasks are wrapped in an `if`.
    if Pkg::Config.build_gem
      # Even if a project builds a gem, if it uses the odd_even or zero-based
      # strategies, we only want to ship final gems because otherwise a
      # development gem would be preferred over the last final gem
      if Pkg::Util::Version.final?
        FileList['pkg/*.gem'].each do |gem_file|
          puts 'This will ship to an internal gem mirror, a public file server, and rubygems.org'
          puts "Do you want to start shipping the rubygem '#{gem_file}'?"
          next unless Pkg::Util.ask_yes_or_no

          Rake::Task['pl:ship_gem_to_rubygems'].execute(file: gem_file)
        end

        Rake::Task['pl:ship_gem_to_downloads'].invoke
      else
        $stderr.puts 'Not shipping development gem using odd_even strategy for the sake of your users.'
      end
    end
  end

  desc 'Ship built gem to internal Gem mirror and public nightlies file server'
  task ship_nightly_gem: 'pl:fetch' do
    # We want to ship a Gem only for projects that build gems, so
    # all of the Gem shipping tasks are wrapped in an `if`.
    if Pkg::Config.build_gem
      fail 'Value `Pkg::Config.gem_host` not defined, skipping nightly ship' unless Pkg::Config.gem_host
      fail 'Value `Pkg::Config.nonfinal_gem_path` not defined, skipping nightly ship' unless Pkg::Config.nonfinal_gem_path

      FileList['pkg/*.gem'].each do |gem_file|
        Pkg::Gem.ship_to_internal_mirror(gem_file)
      end
      Pkg::Util::Execution.retry_on_fail(times: 3) do
        Pkg::Util::Ship.ship_gem('pkg', Pkg::Config.nonfinal_gem_path, platform_independent: true)
      end
    end
  end

  desc 'Ship built gem to rubygems.org'
  task :ship_gem_to_rubygems, [:file] => 'pl:fetch' do |_t, args|
    puts "Do you want to ship #{args[:file]} to rubygems.org?"
    if Pkg::Util.ask_yes_or_no
      puts "Shipping gem #{args[:file]} to rubygems.org"
      Pkg::Util::Execution.retry_on_fail(times: 3) do
        Pkg::Gem.ship_to_rubygems(args[:file])
      end
    end
  end

  desc "Ship built gems to public Downloads server (#{Pkg::Config.gem_host})"
  task :ship_gem_to_downloads => 'pl:fetch' do
    if Pkg::Config.gem_host && Pkg::Config.gem_path
      Pkg::Util::Execution.retry_on_fail(times: 3) do
        Pkg::Util::Ship.ship_gem('pkg', Pkg::Config.gem_path, platform_independent: true)
      end
    else
      warn 'Value `Pkg::Config.gem_host` not defined; skipping shipping to public Download server'
    end
  end

  desc "Ship svr4 packages to #{Pkg::Config.svr4_host}"
  task :ship_svr4 do
    Pkg::Util::Execution.retry_on_fail(:times => 3) do
      if File.directory?("pkg/solaris/10")
        Pkg::Util::Ship.ship_svr4('pkg', Pkg::Config.svr4_path)
      end
    end
  end

  desc "Ship p5p packages to #{Pkg::Config.p5p_host}"
  task :ship_p5p do
    Pkg::Util::Execution.retry_on_fail(:times => 3) do
      if File.directory?("pkg/solaris/11")
        Pkg::Util::Ship.ship_p5p('pkg', Pkg::Config.p5p_path)
      end
    end
  end

  desc "ship apple dmg to #{Pkg::Config.dmg_staging_server}"
  task ship_dmg: 'pl:fetch' do
    path = Pkg::Paths.remote_repo_base(package_format: 'dmg')
    Pkg::Util::Ship.ship_dmg('pkg', path)
  end

  desc "ship nightly apple dmgs to #{Pkg::Config.dmg_staging_server}"
  task ship_nightly_dmg: 'pl:fetch' do
    path = Pkg::Paths.remote_repo_base(package_format: 'dmg', nonfinal: true)
    Pkg::Util::Ship.ship_dmg('pkg', path, nonfinal: true)
  end

  desc "ship Arista EOS swix packages and signatures to #{Pkg::Config.swix_staging_server}"
  task ship_swix: 'pl:fetch' do
    path = Pkg::Paths.remote_repo_base(package_format: 'swix')
    Pkg::Util::Ship.ship_swix('pkg', path)
  end

  desc "ship nightly Arista EOS swix packages and signatures to #{Pkg::Config.swix_staging_server}"
  task ship_nightly_swix: 'pl:fetch' do
    path = Pkg::Paths.remote_repo_base(package_format: 'swix', nonfinal: true)
    Pkg::Util::Ship.ship_swix('pkg', path, nonfinal: true)
  end

  desc "ship tarball and signature to #{Pkg::Config.tar_staging_server}"
  task ship_tar: 'pl:fetch' do
    if Pkg::Config.build_tar
      Pkg::Util::Ship.ship_tar('pkg', Pkg::Config.tarball_path, excludes: ['signing_bundle', 'packaging-bundle'], platform_independent: true)
    end
  end

  desc "ship Windows nuget packages to #{Pkg::Config.nuget_host}"
  task ship_nuget: 'pl:fetch' do
    packages = Dir['pkg/**/*.nupkg']
    if packages.empty?
      $stdout.puts "There aren't any nuget packages in pkg/windows. Maybe something went wrong?"
    else
      Pkg::Nuget.ship(packages)
    end
  end

  desc "Ship MSI packages to #{Pkg::Config.msi_staging_server}"
  task ship_msi: 'pl:fetch' do
    path = Pkg::Paths.remote_repo_base(package_format: 'msi')
    Pkg::Util::Ship.ship_msi('pkg', path, excludes: ["#{Pkg::Config.project}-x(86|64).msi"])
  end

  desc "Ship nightly MSI packages to #{Pkg::Config.msi_staging_server}"
  task ship_nightly_msi: 'pl:fetch' do
    path = Pkg::Paths.remote_repo_base(package_format: 'msi', nonfinal: true)
    Pkg::Util::Ship.ship_msi('pkg', path, excludes: ["#{Pkg::Config.project}-x(86|64).msi"], nonfinal: true)
  end

  desc "Add #{Pkg::Config.project} version #{Pkg::Config.ref} to release-metrics"
  task :update_release_metrics => "pl:fetch" do
    Pkg::Metrics.update_release_metrics
  end

  desc 'UBER ship: ship all the things in pkg'
  task uber_ship: 'pl:fetch' do
    if Pkg::Util.confirm_ship(FileList['pkg/**/*'])
      Rake::Task['pl:ship_rpms'].invoke
      Rake::Task['pl:ship_debs'].invoke
      Rake::Task['pl:ship_dmg'].invoke
      Rake::Task['pl:ship_swix'].invoke
      Rake::Task['pl:ship_nuget'].invoke
      Rake::Task['pl:ship_tar'].invoke
      Rake::Task['pl:ship_svr4'].invoke
      Rake::Task['pl:ship_p5p'].invoke
      Rake::Task['pl:ship_msi'].invoke
      add_shipped_metrics(pe_version: ENV['PE_VER'], is_rc: !Pkg::Util::Version.final?) if Pkg::Config.benchmark
      post_shipped_metrics if Pkg::Config.benchmark
    else
      puts 'Ship canceled'
      exit
    end
  end

  desc 'Create the rolling repo links'
  task create_repo_links: 'pl:fetch' do
    Pkg::Util::Ship.create_rolling_repo_links
  end

  desc 'Create rolling repo links for nightlies'
  task create_nightly_repo_links: 'pl:fetch' do
    Pkg::Util::Ship.create_rolling_repo_links(true)
  end

  desc 'Test out the ship requirements'
  task ship_check: 'pl:fetch' do
    errs = []
    ssh_errs = []
    gpg_errs = []

    if ENV['TEAM']
      unless ENV['TEAM'] == 'release'
        errs << "TEAM environment variable is #{ENV['TEAM']}. It should be 'release'"
      end
    else
      errs << 'TEAM environment variable is not set. This should be set to release'
    end
    # Check SSH access to the staging servers
    ssh_errs << Pkg::Util::Net.check_host_ssh(Pkg::Util.filter_configs('staging_server').values.uniq)
    # Check SSH access to the signing servers, with some windows special-ness
    ssh_errs << Pkg::Util::Net.check_host_ssh(Pkg::Util.filter_configs('signing_server').values.uniq - [Pkg::Config.msi_signing_server])
    ssh_errs << Pkg::Util::Net.check_host_ssh("Administrator@#{Pkg::Config.msi_signing_server}")
    # Check SSH access to the final shipped hosts
    ssh_errs << Pkg::Util::Net.check_host_ssh(Pkg::Util.filter_configs('^(?!.*(?=build|internal)).*_host$').values.uniq)
    ssh_errs.flatten!
    unless ssh_errs.empty?
      ssh_errs.each do |host|
        errs << "Unable to ssh to #{host}"
      end
    end

    # Check for GPG on linux-y systems
    gpg_errs << Pkg::Util::Net.check_host_gpg(Pkg::Config.apt_signing_server, Pkg::Util::Gpg.key)
    gpg_errs << Pkg::Util::Net.check_host_gpg(Pkg::Config.distribution_server, Pkg::Util::Gpg.key)
    gpg_errs.flatten!
    # ignore gpg errors for hosts we couldn't ssh into
    gpg_errs -= ssh_errs
    unless gpg_errs.empty?
      gpg_errs.each do |host|
        errs << "Secret key #{Pkg::Util::Gpg.key} not found on #{host}"
      end
    end

    # For windows and solaris it looks like as long as you have ssh access
    # to the signers you should be able to sign. If this changes in the future
    # we should add more checks here, but for now it should be fine.
    # Check for ability to sign OSX. Should just need to be able to unlock keychain
    begin
      unless ssh_errs.include?(Pkg::Config.osx_signing_server)
        Pkg::Util::Net.remote_execute(
          Pkg::Config.osx_signing_server,
          %(/usr/bin/security -q unlock-keychain -p "#{Pkg::Config.osx_signing_keychain_pw}" "#{Pkg::Config.osx_signing_keychain}"),
          { extra_options: '-oBatchMode=yes' },
        )
      end
    rescue
      errs << "Unlocking the OSX keychain failed! Check the password in your .bashrc on #{Pkg::Config.osx_signing_server}"
    end

    if Pkg::Config.build_gem
      # Do we have rubygems access set up
      if Pkg::Util::File.file_exists?("#{ENV['HOME']}/.gem/credentials")
        # Do we have permissions to publish this gem on rubygems
        unless Pkg::Util::Misc.check_rubygems_ownership(Pkg::Config.gem_name)
          errs << "You don't own #{Pkg::Config.gem_name} on rubygems.org"
        end
      else
        errs << "You haven't set up your .gem/credentials file for rubygems.org access"
      end
    end

    puts "\n\n"
    if errs.empty?
      puts 'Hooray! You should be good for shipping!'
    else
      puts "Found #{errs.length} issues:"
      errs.each do |err|
        puts " * #{err}"
      end
    end
  end

  # It is odd to namespace this ship task under :jenkins, but this task is
  # intended to be a component of the jenkins-based build workflow even if it
  # doesn't interact with jenkins directly.

  # The :target argument is so that we can invoke this task with a
  # subdirectory of the standard distribution server path. That way we
  # can separate out built artifacts from signed/actually shipped
  # artifacts: "$path/shipped" vs "$path/artifacts"
  namespace :jenkins do
    # For Artifactory, collect artifacts and metadata into a local "artifacts" directory,
    # then create and upload a tarball of that directory.
    desc '(deprecated): use pl:jenkins:ship'
    task :ship_to_artifactory, :local_dir do |_t, args|
      puts "Warning: 'ship_to_artifactory' task is deprecated. " \
           "Shipping to Artifactory is part of 'pl:jenkins:ship' task."
    end

    # For the distribution server, collect artifacts and metadata into a local "artifacts"
    # directory, then rsync the tree to the distribution server.
    desc 'Ship "artifacts" directory contents to distribution server'
    task :ship, :target, :local_dir do |_t, args|
      local_dir = args.local_dir || 'pkg'
      target = args.target || 'artifacts'

      Pkg::Util::RakeUtils.invoke_task('pl:fetch')

      Pkg::Ship::DistributionServer.ship(local_dir, target)
      Pkg::Ship::Artifactory.ship(local_dir, target)
    end

    desc 'Ship generated repository configs to the distribution server'
    task :ship_repo_configs do
      Pkg::Deb::Repo.ship_repo_configs
      Pkg::Rpm::Repo.ship_repo_configs
    end
  end
end
