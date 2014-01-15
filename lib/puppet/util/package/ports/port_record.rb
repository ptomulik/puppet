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
# sources (currently from options files).
#
class PortRecord < ::Puppet::Util::Package::Ports::Record

  # These fields may are obtained from search back-end without additional
  # effort (without {#amend!}).
  # @note The method must be implemented in a subclass.
  # @return [Array]
  #
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

  # These fields are requested from underlying search method by default (when
  # user does not specify what fields to request).
  #
  # Note, that this list may include {std_fields} plus some extra fields
  # generated by {#amend!}.
  #
  # @note The method must be implemented in a subclass.
  # @return [Array]
  #
  def self.default_fields
    [
      :pkgname,
      :portname,
      :portorigin,
      :path,
      :options_file,
    ]
  end

  # Dependencies between fields.
  #
  # If we want {#amend!} to add extra fields to PortRecord we must first
  # ensure that we request certain fields from `make search`. For example, to
  # determine `:pkgname` one needs to include `:name` field in the `make
  # search` result, that is the search command should be like
  #
  #   `make search -C /usr/ports <filter> display=name,...`
  #
  # This hash describes these dependencies, see also {Record.deps_for_amend}.
  #
  # See [ports(7)](http://www.freebsd.org/cgi/man.cgi?query=ports&sektion=7)
  # for more information about `make search`.
  # @return [Hash]
  #
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
  # @return [Array]
  #
  def self.search_keys
    std_fields + std_fields.collect {|f| ("x" + f.id2name).intern }
  end

  # Add extra fields to initially filled-in PortRecord.
  #
  # Most of the extra fields that can be added do not introduce any new
  # information in fact - they're just computed from already existing fields.
  # The exception is the `:options` field. Options are loaded from existing
  # port options files (`/var/db/ports/*/options{,.local}`).
  #
  # **Example:**
  #
  #     fields = [:portorigin, :options]
  #     record = PortRecord.parse(paragraph)
  #     record.amend!(fields)
  #
  # @param fields [Array] list of fields to be included in output
  # @return self
  # @see Record.amend!
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

  # ---
  # FN - Field Name, FV - Field Value, FX - Field (composed)
  # +++
  
  # Regular expression to match field names in paragraphs returned by `make
  # search` command.
  self::FN_RE = /[a-zA-Z0-9_-]+/
  # Regular expression to match field values in paragraphs returned by `make
  # search` command.
  self::FV_RE = /(?:(?:\S?.*\S)|)/
  # Regular expression to match whole field (field name with field value) in
  # paragraphs returned by `make search` command.
  self::FX_RE = /^\s*(#{self::FN_RE})\s*:[ \t]*(#{self::FV_RE})\s*$/

  # Parse a paragraph and return port record.
  #
  # @param paragraph [String]
  # @param options [Hash]
  # @option options :moved [Boolean] what to do with ports that were moved or
  #   removed. By default the search method discards records for ports that
  #   have 'Moved' field. If :moved is `true`, these records will be included
  #   in search result as well.
  # @return [PortRecord]
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
