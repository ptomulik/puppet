require 'facter'
require 'puppet/util/package'
require 'puppet/util/package/ports/port_search'
require 'puppet/util/package/ports/pkg_search'


# Utilities for FreeBSD ports management.
#
# This module includes {PortSearch} and {PkgSearch} modules to help searching
# through ports and packages.
#
# The following conventions are used:
#
# * a *portname* is a base name of a port, such as `'ruby'`,
# * a *portorigin* is an unambiguous port name in form `'lang/ruby18'`,
# * a *pkgname* is a name of binary package, for example: `'ruby-1.8.7.371,1'`
#
# On BSD system we have these two "databases":
#
# 1. Ports - index of source packages ready to compile and install.
# 2. Packages - index of binary (installed) packages (includes installed ports).
#
# An installed port appears in package database, but the correspondence between
# records in these databases is little bit messy. There are quite lot of
# gotchas, for example the following situations  may occur:
#
# 1. A package exists in package database but its port has been removed from
#    ports collection (a totally outdated package).
# 2. Ports `'lang/ruby18'` and `'lang/ruby19'` exist and have common portname
#    `'ruby'`. When installed, the corresponding packages have pkgnames
#    `ruby-1.8.7.371,1` and `ruby-1.9.3.448,1` respectivelly, but they are
#    undistinguishable by the portname.
# 3. Port `'lang/perl5.14'` exists (*portname* == `'perl'`) and its `Makefile`
#    sets PKGNAMESUFFIX=`'threaded'`. When installed, the resulting package is
#    named `'perl-threaded-5.14.4'`.
# 4. The basename of port may change. For example, it happened to me with the
#    `mysql-client` package, which was "upgraded" to `mysql55-client`.
#
# Naming rules are described at {http://www.freebsd.org/doc/en/books/porters-handbook/makefile-naming.html}
#
# My (Pawel Tomulik) personal opinion is that the best way to identify ports is
# through their portorigins. It's robust to most of the above gotchas, so it
# should be used to identify instances of `package` provider as well as to
# identify packages in puppet manifests.
#
module Puppet::Util::Package::Ports

  include PortSearch
  include PkgSearch

end
