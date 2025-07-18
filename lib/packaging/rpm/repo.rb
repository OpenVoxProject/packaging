# Utilities for working with rpm repos
require 'fileutils'
require 'find'

module Pkg::Rpm::Repo
  class << self
    def base_url
      "http://#{Pkg::Config.builds_server}/#{Pkg::Config.project}/#{Pkg::Config.ref}"
    end

    def ship_repo_configs(target = "repo_configs")
      if Pkg::Util::File.empty_dir?("pkg/#{target}/rpm")
        warn "No repo configs have been generated! Try pl:rpm_repo_configs."
        return
      end

      Pkg::Util::RakeUtils.invoke_task("pl:fetch")
      repo_dir = "#{Pkg::Config.jenkins_repo_path}/#{Pkg::Config.project}/#{Pkg::Config.ref}/#{target}/rpm"
      Pkg::Util::Net.remote_execute(Pkg::Config.distribution_server, "mkdir -p #{repo_dir}")
      Pkg::Util::Execution.retry_on_fail(:times => 3) do
        Pkg::Util::Net.rsync_to("pkg/#{target}/rpm/", Pkg::Config.distribution_server, repo_dir)
      end
    end

    def repo_creation_command(repo_directory, artifact_paths = nil)
      cmd = "[ -d #{repo_directory} ] || exit 1 ; "
      cmd << "pushd #{repo_directory} > /dev/null && "
      cmd << 'echo "Checking for running repo creation. Will wait if detected." && '
      cmd << 'while [ -f .lock ] ; do sleep 1 ; echo -n "." ; done && '
      cmd << 'echo "Setting lock" && '
      cmd << 'touch .lock && '
      cmd << 'createrepo=$(which createrepo) ; '

      # Added for compatibility.
      # The nightly repo ships operate differently and do not want to be calculating
      # the correct paths based on which packages are available on the distribution
      # host, we just want to be `createrepo`ing for what we've staged locally
      #
      # We should only assume repo_directory exists locally if we didn't pass
      # artifact paths
      if artifact_paths.nil?
        # Since the command already has a `pushd #{repo_directory}` let's make sure
        # we're calculating artifact paths relative to that.
        Dir.chdir repo_directory do
          artifact_paths = Dir.glob('**/*.rpm').map { |package| File.dirname(package) }
        end
      end

      artifact_paths.each do |path|
        next if path.include? 'aix'

        cmd << "if [ -d #{path}  ]; then "
        cmd << "pushd #{path} && "
        cmd << '$createrepo --checksum=sha --checkts --update --delta-workers=0 --database . && '
        cmd << 'popd ; '
        cmd << 'fi ;'
      end
      cmd
    end

    # @deprecated this command will die a painful death when we are
    #   able to sit down with Operations and refactor our distribution infra.
    #   At a minimum, it should be refactored alongside its Debian counterpart
    #   into something modestly more generic.
    #   - Ryan McKern 11/2015
    #
    # @param origin_path [String] path for RPM repos on local filesystem
    # @param destination_path [String] path for RPM repos on remote filesystem
    # @param destination [String] remote host to send rsynced content to. If
    #        nil will copy locally
    # @param dryrun [Boolean] whether or not to use '--dry-run'
    #
    # @return [String] an rsync command that can be executed on a remote host
    #   to copy local content from that host to a remote node.
    def repo_deployment_command(origin_path, destination_path, destination, dryrun = false)
      path = Pathname.new(origin_path)
      dest_path = Pathname.new(destination_path)

      options = %w(
        rsync
        --recursive
        --links
        --hard-links
        --update
        --human-readable
        --itemize-changes
        --progress
        --verbose
        --super
        --delay-updates
        --omit-dir-times
        --no-perms
        --no-owner
        --no-group
      )

      options << '--dry-run' if dryrun
      options << path

      if destination
        options << "#{destination}:#{dest_path.parent}"
      else
        options << "#{dest_path.parent}"
      end

      options.join("\s")
    end

    def sign_repos(directory)
      files_to_sign = Find.find(directory).select { |file| file.match(/repomd.xml$/) }
      files_to_sign.each do |file|
        Pkg::Util::Gpg.sign_file(file)
      end
    end

    def retrieve_repo_configs(target = "repo_configs")
      wget = Pkg::Util::Tool.check_tool("wget")
      FileUtils.mkdir_p("pkg/#{target}")
      config_url = "#{base_url}/#{target}/rpm/"
      begin
        stdout, = Pkg::Util::Execution.capture3("#{wget} -r -np -nH --cut-dirs 3 -P pkg/#{target} --reject 'index*' #{config_url}")
        stdout
      rescue => e
        fail "Couldn't retrieve rpm yum repo configs.\n#{e}"
      end
    end

    # Generate yum configuration files that point to the repositories created
    # on the distribution server with packages created from the current source
    # repo commit. There is one for each dist/version that is packaged (e.g.
    # el5, el6, etc). Files are created in pkg/repo_configs/rpm and are named
    # pl-$project-$sha.conf, and can be placed in /etc/yum.repos.d to enable
    # clients to install these packages.
    #
    def generate_repo_configs(source = "repos", target = "repo_configs", signed = false)
      # We have a hard requirement on wget because of all the download magicks
      # we have to do
      #
      wget = Pkg::Util::Tool.check_tool("wget")

      # This is the standard path to all build artifacts on the distribution
      # server for this commit
      #
      repo_base = "#{base_url}/#{source}/"

      # First check if the artifacts directory exists
      #

      # We have to do two checks here - first that there are directories with
      # repodata folders in them, and second that those same directories also
      # contain rpms
      #
      stdout, = Pkg::Util::Execution.capture3("#{wget} --spider -r -l 5 --no-parent #{repo_base} 2>&1")
      stdout = stdout.split.uniq.reject { |x| x =~ /\?|index/ }.select { |x| x =~ /http:.*repodata\/$/ }

      # RPMs will always exist at the same directory level as the repodata
      # folder, which means if we go up a level we should find rpms
      #
      yum_repos = []
      stdout.map { |x| x.chomp('repodata/') }.each do |url|
        output, = Pkg::Util::Execution.capture3("#{wget} --spider -r -l 1 --no-parent #{url} 2>&1")
        unless output.split.uniq.reject { |x| x =~ /\?|index/ }.select { |x| x =~ /http:.*\.rpm$/ }.empty?
          yum_repos << url
        end
      end

      if yum_repos.empty?
        warn "No rpm repos were found to generate configs from!"
        return
      end

      FileUtils.mkdir_p(File.join("pkg", target, "rpm"))

      # Parse the rpm configs file to generate repository configs. Each line in
      # the rpm_configs file corresponds with a repo directory on the
      # distribution server.
      #
      yum_repos.each do |url|
        # We ship a base 'srpm' that gets turned into a repo, but we want to
        # ignore this one because its an extra
        next if url == "#{repo_base}srpm/"

        platform_tag = Pkg::Paths.tag_from_artifact_path(url)
        platform, version, arch = Pkg::Platforms.parse_platform_tag(platform_tag)

        # Create an array of lines that will become our yum config
        #
        config = ["[pl-#{Pkg::Config.project}-#{Pkg::Config.ref}]"]
        config << ["name=PL Repo for #{Pkg::Config.project} at commit #{Pkg::Config.ref}"]
        config << ["baseurl=#{url}"]
        config << ["enabled=1"]
        if signed
          config << ["gpgcheck=1"]
          config << ["gpgkey=http://#{Pkg::Config.builds_server}/#{Pkg::Util::Gpg.key}"]
        else
          config << ["gpgcheck=0"]
        end

        # Write the new config to a file under our repo configs dir
        #
        config_file = File.join("pkg", target, "rpm", "pl-#{Pkg::Config.project}-#{Pkg::Config.ref}-#{platform}-#{version}-#{arch}.repo")
        File.open(config_file, 'w') { |f| f.puts config }
      end
      puts "Wrote yum configuration files for #{Pkg::Config.project} at #{Pkg::Config.ref} to pkg/#{target}/rpm"
    end

    def create_local_repos(directory = "repos")
      stdout, = Pkg::Util::Execution.capture3("bash -c '#{repo_creation_command(directory)}'")
      stdout
    end

    def create_remote_repos(directory = 'repos')
      artifact_directory = File.join(Pkg::Config.jenkins_repo_path, Pkg::Config.project, Pkg::Config.ref)
      artifact_paths = Pkg::Repo.directories_that_contain_packages(File.join(artifact_directory, 'artifacts'), 'rpm')
      Pkg::Repo.populate_repo_directory(artifact_directory)
      command = Pkg::Rpm::Repo.repo_creation_command(File.join(artifact_directory, directory), artifact_paths)

      begin
        Pkg::Util::Net.remote_execute(Pkg::Config.distribution_server, command)
        # Now that we've created our package repositories, we can generate repo
        # configurations for use with downstream jobs, acceptance clients, etc.
        Pkg::Rpm::Repo.generate_repo_configs

        # Now that we've created the repo configs, we can ship them
        Pkg::Rpm::Repo.ship_repo_configs
      ensure
        # Always remove the lock file, even if we've failed
        Pkg::Util::Net.remote_execute(Pkg::Config.distribution_server, "rm -f #{artifact_directory}/repos/.lock")
      end
    end

    def create_repos_from_artifacts(directory = "repos")
      Pkg::Util.deprecate('Pkg::Rpm::Repo.create_repos_from_artifacts', 'Pkg::Rpm::Repo.create_remote_repos')
      create_remote_repos(directory)
    end

    def create_repos(directory = "repos")
      Pkg::Util.deprecate('Pkg::Rpm::Repo.create_repos', 'Pkg::Rpm::Repo.create_local_repos')
      create_local_repos(directory)
    end

    # @deprecated this command is exactly as awful as you think it is.
    #   -- Ryan McKern 12/2015
    #
    # @param yum_path [String] path for rpm repos on local and remote filesystem
    # @param origin_server [String] remote host to start the  rsync from
    # @param destination_server [String] remote host to send rsynced content to
    # @param dryrun [Boolean] whether or not to use '--dry-run'
    def deploy_repos(yum_path, origin_server, destination_server, dryrun = false)
      rsync_command = repo_deployment_command(yum_path, yum_path, destination_server, dryrun)

      Pkg::Util::Net.remote_execute(origin_server, rsync_command)
    end
  end
end
