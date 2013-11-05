Puppet::Type.type(:package).provide :ports, :parent => :freebsd, :source => :freebsd do
  desc "Support for FreeBSD's ports. Note that this, too, mixes packages and ports.

  `install_options` are passed to `portupgrade` command when installing,
  reinstalling or upgrading packages. You shall include `['-M','BATCH=yes']` in
  almost all cases when providing `install_options` by your own. Some CLI flags
  are prepended internally to CLI and some flags given by user are internally
  removed when performing install, reinstall or upgrade actions.  Install
  always prepends `-N` and removes `-R` and `-f` if provided by user. Reinstall
  always prepends `-f` and removes `-N` flag if present. Upgrade always removes
  `-N` and `-f` if present in install_options.

  `uninstall_options` are passed to pkg_deinstall command when package gets
  uninstalled (for pkg package database). Probably the most commonly used
  uninstall option is the `-r` option which uninstalls recursively all packages
  that depend on the one being uninstalled.

  `build_options` shall be a hash with port's option names as keys (all
  uppercase) and boolean values. This parameter defines options that you would
  normally set with make config command (the blue ncurses interface). Here is an
  example:

      package { 'www/apache22':
        ensure => present,
        build_options => { 'SUEXEC' => true }
      }

  The options are written to `/var/db/ports/*/options.local` files (one file
  per package). They are synchronized with what is found in
  `/var/db/ports/*/options{,.local}` files (possibly several files files per
  package). If the build_options of already installed packages are out of sync
  with these provided in puppet manifests, the package gets reinstalled with
  the options defined in puppet manifests.
  "
  commands :portupgrade   => "/usr/local/sbin/portupgrade",
           :portversion   => "/usr/local/sbin/portversion",
           :portuninstall => "/usr/local/sbin/pkg_deinstall",
           :make          => "/usr/bin/make"

  defaultfor :operatingsystem => :freebsd

  has_feature :install_options
  has_feature :uninstall_options

  # I hate ports
  %w{INTERACTIVE UNAME}.each do |var|
    ENV.delete(var) if ENV.include?(var)
  end

  require 'puppet/util/package/ports'
  require 'puppet/util/package/ports/options'
  extend Puppet::Util::Package::Ports

  # note, portsdir and port_dbdir are defined in module
  # Puppet::Util::Package::Ports
  confine :exists => [ self.portsdir, self.port_dbdir ]

  def self.instances(names=nil)
    records = {}
    # find installed packages
    search_packages(names) do |record|
      records[record[:pkgname]] ||= Array.new
      if record[:portorigin] and ['<','=','>'].include?(record[:portstatus])
        records[record[:pkgname]] << record
      end
    end
    # create provider instances
    packages = []
    records.each do |pkgname, recs|
      if (len = recs.length) > 0
        rec = recs.last
        if len > 1
          # in theory this should never happen, but it's better to know
          warning "Found #{len} installed ports named '#{pkgname}': " +
            "#{recs.map{|r| "'#{r[:portorigin]}'"}.join(', ')}. " +
            "Only '#{rec[:portorigin]}' will be processed."
        end
        package = new({
          :name => rec[:portorigin],
          :ensure => rec[:pkgversion],
          :build_options => rec[:options],
          :provider => self.name
        })
        package.assign_port_attributes(rec)
        packages << package
      else
        warning "Could not find port for installed package '#{pkgname}'." +
                 "Build options will not work for this package."
      end
    end
    packages
  end

  def self.prefetch(packages)
    # already installed packages
    newpkgs = packages.keys
    instances.each do |prov|
      if pkg = (packages[prov.name] || packages[prov.portorigin] ||
                packages[prov.pkgname] || packages[prov.portname])
        newpkgs -= [prov.name, prov.portorigin, prov.pkgname, prov.portname]
        pkg.provider = prov
      end
    end
    # we prefetch also not installed ports to save time; this way we perform
    # only two or three calls to `make search` (for up to 60 packages) instead
    # of 3xN calls (in query()) for N packages
    search_ports(newpkgs) do |name,record|
      prov = new({:name => record[:portorigin], :ensure => :absent})
      prov.assign_port_attributes(record)
      packages[name].provider = prov
    end
  end

  self::PORT_ATTRIBUTES = [
    :pkgname,
    :portorigin,
    :portname,
    :portstatus,
    :portinfo,
    :options_file,
    :options_files
  ]

  self::PORT_ATTRIBUTES.each do |attr|
    define_method(attr) do
      var = instance_variable_get("@#{attr}".intern)
      unless var
        raise Puppet::Error, "Attribute '#{attr}' not assigned for package '#{self.name}'."
      end
      var
    end
  end

  # assign attributes from hash (but only these listed in PORT_ATTRIBUTES)
  def assign_port_attributes(record)
    (record.keys & self.class::PORT_ATTRIBUTES).each do |key|
      instance_variable_set("@#{key}".intern, record[key])
    end
  end

  # needed by Puppet::Type::Package
  def build_options_validate(opts)
    return true if not opts # options not defined
    options_class = Puppet::Util::Package::Ports::Options
    unless opts.is_a?(Hash) or opts.is_a?(options_class)
      fail ArgumentError, "#{opts.inspect} of type #{opts.class} is not an " +
                          "options Hash (for $build_options)"
    end
    opts.each do |k, v|
      unless options_class.option_name?(k)
        fail ArgumentError, "#{k.inspect} is not a valid option name (for " +
                            "$build_options)"
      end
      unless options_class.option_value?(v)
        fail ArgumentError, "#{v.inspect} is not a valid option value (for " +
                            "$build_options)"
      end
    end
    true
  end

  # needed by Puppet::Type::Package
  def build_options_munge(opts)
    unless opts.is_a?(Puppet::Util::Package::Ports::Options)
      Puppet::Util::Package::Ports::Options[opts || {}]
    else
      opts
    end
  end

  # needed by Puppet::Type::Package
  def build_options_insync?(should, is)
    unless should.is_a?(Puppet::Util::Package::Ports::Options) and
               is.is_a?(Puppet::Util::Package::Ports::Options)
      return false
    end
    is.select {|k,v| should.keys.include? k} == should
  end

  # needed by Puppet::Type::Package
  def build_options_should_to_s(should, newvalue)
    if newvalue.is_a?(Puppet::Util::Package::Ports::Options)
      Puppet::Util::Package::Ports::Options[newvalue.sort].inspect
    else
      newvalue.inspect
    end
  end

  # needed by Puppet::Type::Package
  def build_options_is_to_s(should, currentvalue)
    if currentvalue.is_a?(Puppet::Util::Package::Ports::Options)
      hash = currentvalue.select{|k,v| should.keys.include? k}.sort
      Puppet::Util::Package::Ports::Options[hash].inspect
    else
      currentvalue.inspect
    end
  end

  # Interface method required by package resource type. Returns the current
  # value of build_options property.
  def build_options
    properties[:build_options]
  end

  # Reinstall package to deploy (new) build options.
  def build_options=(opts)
    reinstall(opts)
  end

  def sync_build_options(should)
    return if not should
    is = properties[:build_options]
    unless build_options_insync?(should, is)
      should.save(options_file, { :pkgname => pkgname })
    end
  end
  private :sync_build_options

  def revert_build_options
    if options = properties[:build_options]
      debug "Reverting options in #{options_file}"
      properties[:build_options].save(options_file, { :pkgname => pkgname })
    end
  end
  private :revert_build_options

  # Default options for {#install} method.
  self::DEFAULT_INSTALL_OPTIONS = %w{-N -M BATCH=yes}
  # Default options for {#reinstall} method.
  self::DEFAULT_REINSTALL_OPTIONS = %w{-r -f -M BATCH=yes}
  # Default options for {#update} method.
  self::DEFAULT_UPGRADE_OPTIONS = %w{-R -M BATCH=yes}
  # Default options for {#uninstall} method.
  self::DEFAULT_UNINSTALL_OPTIONS =  %w{}

  # Return portupgrade's CLI options for use within the {#install} method.
  def install_options
    # In an ideal world we would have all these parameters independent:
    # install_options, reinstall_options, upgrade_options, uninstall_options.
    # In this world we must live with install_options and uninstall_options
    # only.
    ops = resource[:install_options]
    # We always add -N to command line to indicate, that we want to install new
    # package only when it's not installed. This idea is inherited from
    # original implementation of ports provider.
    # We always remove -R and -f from command line, as these options have
    # no clear meaning when -N is used (either, they have no effect with -R or
    # they can mess-up your OS - I haven't checked this).
    prepare_options(ops, self.class::DEFAULT_INSTALL_OPTIONS, %w{-N}, %w{-R -f})
  end

  # Return portupgrade's CLI options for use within the {#reinstall} method.
  def reinstall_options
    ops = resource[:install_options]
    # We always remove -N from command line, as this flag breaks the upgrade
    # procedure (-N indicates that one wants to install new package which is
    # currently not installed, or to skip installation if it's installed; the
    # reinstall method is invoked on already installed packages only).
    # We always add -f to command line, to not silently skip reinstall (without
    # this reinstalls are silently discarded)
    prepare_options(ops, self.class::DEFAULT_REINSTALL_OPTIONS, %w{-f}, %w{-N})
  end

  # Return portupgrade's CLI options for use within the {#update} method.
  def upgrade_options
    ops = resource[:install_options]
    # We always remove -N from command line, as this flag breaks the upgrade
    # procedure (-N indicates that one wants to install package which is not
    # currently installed, or to skip installation if it's installed; the
    # upgrade method is invoked on already installed packages only).
    # We always remove -f from command line, as the upgrade procedure shouldn't
    # depend on it (upgrade should only be used to install newer versions,
    # which must work without -f)
    prepare_options(ops, self.class::DEFAULT_UPGRADE_OPTIONS, %w{}, %w{-f -N})
  end

  # Return portuninstall's CLI options for use within the {#uninstall} method.
  def uninstall_options
    ops = resource[:uninstall_options]
    prepare_options(ops, self.class::DEFAULT_UNINSTALL_OPTIONS)
  end

  # Prepare options for install, reinstall, upgrade and uninstall methods.
  #
  # @param options [Array|nil]
  # @param defaults [Array] default flags used when options are not provided,
  # @param extra [Array] extra flags added to user-defined options,
  # @param deny [Array] flags that must be removed from user-defined options,
  # @return [Array] modified options
  #
  # Returns defaults if options are not provided by user. If options are
  # provided, handle the '{option => value}' pairs, flatten options array
  # append extra flags defined by caller and remove denied flags defined by the
  # caller.
  #
  def prepare_options(options, defaults, extra = [], deny = [])
    return defaults unless options

    # handle {option => value} hashes and flatten nested arrays
    options = options.collect do |val|
      case val
      when Hash
        val.keys.sort.collect { |k| "#{k}=#{val[k]}" }
      else
        val
      end
    end.flatten

    # add some flags we think are mandatory for the given operation
    extra.each { |f| options.unshift(f) unless options.include?(f) }
    options = options - deny
    options
  end

  # For internal use only
  def do_portupgrade(name, args, build_options)
    cmd = args << name
    begin
      sync_build_options(build_options)
      output = portupgrade(*cmd)
      if output =~ /\*\* No such /
        raise Puppet::ExecutionFailure, "Could not find package #{name}"
      end
    rescue
      revert_build_options
      raise
    end
  end
  private :do_portupgrade

  # install new package (only if it's not installed).
  def install
    name = @portorigin || resource[:name]
    # we prefetch also not installed ports so `portorigin` should be available
    do_portupgrade name, install_options, resource[:build_options]
  end

  # reinstall already installed package with new options.
  def reinstall(options)
    do_portupgrade portorigin, reinstall_options, options
  end

  # upgrade already installed package.
  def update
    if properties[:ensure] == :absent
      install
    else
      do_portupgrade portorigin, upgrade_options, resource[:build_options]
    end
  end

  # uninstall already installed package
  def uninstall
    cmd = uninstall_options << self.pkgname
    portuninstall(*cmd)
  end

  # If there are multiple packages, we only use the last one
  def latest
    # If there's no "latest" version, we just return a placeholder
    result = :latest
    status, info, portname, oldversion = [nil, nil, nil, nil]
    oldversion = properties[:ensure]
    case portstatus
    when '>','='
      result = oldversion
    when '<'
      if m = portinfo.match(/\((\w+) has (.+)\)/)
        source, newversion = m[1,2]
        debug "Newer version in #{source}"
        result = newversion
      else
        raise Puppet::Error, "Could not match version info '#{portinfo}'"
      end
    when '?'
      warning "The installed package #{pkgname} does not appear in the " +
        "ports database nor does its port directory exist."
    when '!'
      warning "The installed package #{pkgname} does not appear in the " +
        "ports database, the port directory actually exists, but the latest " +
        "version number cannot be obtained."
    when '#'
      warning "The installed package #{pkgname} does not have an origin recorded."
    else
      warning "Invalid status flag '#{portstatus}' for package " +
        "#{pkgname} (returned by portversion command)."
    end
    result
  end

  def query
    # support names, portorigin, pkgname and portname
    (inst = self.class.instances([name]).last) ? inst.properties : nil
  end
end
