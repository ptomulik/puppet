require 'puppet/util/package'

module Puppet::Util::Package::Ports
# Several utlility functions used by other ports-related modules.
module Functions

  # Regular expression used to match portname.
  PORTNAME_RE    = /[a-zA-Z0-9][\w\.+-]*/
  # Regular expression used to match package version suffix.
  PORTVERSION_RE = /[a-zA-Z0-9][\w\.,]*/
  # Regular expression used to match pkgname.
  PKGNAME_RE     = /(#{PORTNAME_RE})-(#{PORTVERSION_RE})/
  # Regular expression used to match portorigin.
  PORTORIGIN_RE  = /(#{PORTNAME_RE})\/(#{PORTNAME_RE})/

  # Escape string that is to be used as a search pattern.
  # This search pattern is used by BSD ports' Makefile. It's not ruby Regexp.
  def escape_pattern(pattern)
    # it's also advisable to validate user's input with pkgname?, portname? or
    # potorigin?
    pattern.gsub(/([\(\)\.\*\[\]\|])/) {|c| '\\' + c}
  end

  # Convert port/package name (or array of names) to search pattern for `"make
  # search"` command.
  def strings_to_pattern(name)
    if name.is_a?(Enumerable) and not name.instance_of?(String)
      '(' + name.map{|p| escape_pattern(p)}.join('|') + ')'
    else
      escape_pattern(name)
    end
  end

  # Convert *pkgnames* to search pattern for `"make search"` command.
  def fullname_to_pattern(names)
    "^#{strings_to_pattern(names)}$"
  end

  # Convert *portorigins* to search pattern for `"make search"` command.
  def portorigin_to_pattern(origins)
    "^#{portsdir}/#{strings_to_pattern(origins)}$"
  end

  # Convert *pkgnames* to search pattern for `"make search"` command.
  def pkgname_to_pattern(pkgnames)
    fullname_to_pattern(pkgnames)
  end

  # Convert *portnames* to search pattern for search_ports().
  def portname_to_pattern(portnames)
    version_pattern = '[a-zA-Z0-9][a-zA-Z0-9\\.,_]*'
    "^#{strings_to_pattern(portnames)}-#{version_pattern}$"
  end

  # Convert *portorigins*, *pkgnames* or *portnames* to search pattern
  def mk_search_pattern(key, names)
    case key
    when :pkgname
      pkgname_to_pattern(names)
    when :portname
      portname_to_pattern(names)
    when :portorigin
      portorigin_to_pattern(names)
    else
      fullname_to_pattern(names)
    end
  end

  # Path to BSD ports source, `/usr/pkgsrc` on NetBSD, `/usr/ports` on other
  # systems. Set `ENV['PORTSDIR']` to override defaults.
  def portsdir
    unless dir = ENV['PORTSDIR']
      os = Facter.value(:operatingsystem)
      dir = (os == "NetBSD") ? '/usr/pkgsrc' : '/usr/ports'
    end
    dir
  end

  # Path to ports DB directory, defaults to `/var/db/ports`.
  # Set `ENV['PORT_DBDIR']` to override default value.
  def port_dbdir
    unless dir = ENV['PORT_DBDIR']
      dir = '/var/db/ports'
    end
    dir
  end

  # Is this string a well-formed port's origin?
  def portorigin?(string)
    string.is_a?(String) and string =~ /^#{PORTORIGIN_RE}$/
  end

  # Is this string a well-formed port's pkgname?
  def pkgname?(string)
    string.is_a?(String) and string =~ /^#{PKGNAME_RE}$/
  end

  # Is this string a well-formed portname?
  def portname?(string)
    string.is_a?(String) and string =~ /^#{PORTNAME_RE}$/
  end

  # Split *pkgname* into *portname* and *portversion*.
  def split_pkgname(pkgname)
    if m = /^#{PKGNAME_RE}$/.match(pkgname)
      m.captures
    else
      [pkgname, nil]
    end
  end

  # Return supported names of option files for a port. The returned names are
  # in same order as they are read by ports Makefile's. The last file overrides
  # values defined in all previous file, so  it's most significant.
  def options_files(portname, portorigin)
      [
        # keep these in proper order, see /usr/ports/Mk/bsd.options.mk
        portname,                  # OPTIONSFILE,
        portorigin.gsub(/\//,'_'), # OPTIONS_FILE,
      ].flatten.map{|x|
        f = File.join(self.port_dbdir,x,"options")
        [f,"#{f}.local"]
      }.flatten
  end
end
end
