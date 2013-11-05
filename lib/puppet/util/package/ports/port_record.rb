require 'puppet/util/package'
require 'puppet/util/package/ports/record'

module Puppet::Util::Package::Ports

# Represents single record returned by {PortSearch#search_ports}.
#
# This is a (kind of) hash which holds results parset from `make search` output
# (searching FreeBSD [ports(7)](http://www.freebsd.org/cgi/man.cgi?query=ports&sektion=7)).
# The `make search` commands searches available ports (FreeBSDs source packages
# that may be compiled and installed) and outputs one paragraph (record) per
# port. The paragraph lines have "Field: value" form.
#
# The assumption is that user first parses record with {PortRecord.parse}
# and then optionally adds some extra fields/refines the record with {#amend!}.
# The {#amend!} method "computes" some of the extra fields based on values
# already present in PortRecord. The `:options` are retrieved from additional
# sources (from options files in case of *pkg* backend).
#
class PortRecord < ::Puppet::Util::Package::Ports::Record

  # TODO: write documentation
  def self.std_fields
    [
      :name,
      :path,
      :info,
      :maint,
      :cat,
      :bdeps,
      :rdeps,
      :www
    ]
  end

  # Fields requested by default from {PortSearch#search_ports}
  def self.default_fields
    [
      :pkgname,
      :portname,
      :portorigin,
      :path,
      :options_file,
    ]
  end

  # If we want {#amend!} to add extra fields to PortRecord we must first
  # ensure that we request certain fields from `make search`. For example, to
  # determine `:pkgname` one needs to include `:name` field in the `make
  # search` result, that is the search command should be like
  #
  #   `make search -C /usr/ports <filter> display=name,...`
  #
  # The following hash describes these dependencies.
  #
  # See [ports(7)](http://www.freebsd.org/cgi/man.cgi?query=ports&sektion=7)
  # for more information about `make search`.
  def self.deps_for_amend
    {
      :options        => [:name, :path],
      :options_file   => [:name, :path],
      :options_files  => [:name, :path],
      :pkgname        => [:name],
      :portname       => [:name],
      :portorigin     => [:path],
      :portversion    => [:name],
    }
  end

  # Field names that may be used as search keys in 'make search'
  def self.search_keys
    std_fields + std_fields.collect {|f| ("x" + f.id2name).intern }
  end

  # Add extra fields to initially filled-in PortRecord.
  #
  # @param fields [Array] list of fields to be included in output
  # @return self
  #
  # Most of the extra fields that can be added do not introduce any new
  # information in fact - they're just computed from already existing fields.
  # The exception is the `:options` field. Options are loaded from existing
  # port options files (`/var/db/ports/*/options{,.local}).
  #
  # **Example:**
  #
  #     fields = [:portorigin, :options]
  #     record = PortRecord.parse(paragraph)
  #     record.amend!(fields)
  #
  def amend!(fields)
    if self[:name]
      self[:pkgname] = self[:name]
      self[:portname], self[:portversion] = self.class.split_pkgname(self[:name])
    end
    if self[:path]
      self[:portorigin] = self[:path].split(/\/+/).slice(-2..-1).join('/')
    end
    super
  end

  # FN - Field Name, FV - Field Value, FX - Field (composed)
  self::FN_RE = /[a-zA-Z0-9_-]+/
  self::FV_RE = /(?:(?:\S?.*\S)|)/
  self::FX_RE = /^\s*(#{self::FN_RE})\s*:[ \t]*(#{self::FV_RE})\s*$/

  # Parse a paragraph and return port record.
  def self.parse(paragraph, options={})
    return nil if paragraph =~ /^Moved:/ and not options[:moved]
    keymap = { :port => :name }
    hash = paragraph.scan(self::FX_RE).map{|c|
      key, val = [c[0].sub(/[-]/,'').downcase.intern, c[1]]
      key = keymap[key] if keymap.include?(key)
      [key, val]
    }
    PortRecord[ hash ]
  end
end
end
