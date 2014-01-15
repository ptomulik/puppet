require 'puppet/util/package'

module Puppet::Util::Package::Ports
# This is a superclass for {PortRecord} and {PkgRecord}. Represents a single
# record returned by search (either ports INDEX or package database search).
#
# There are a few search methods defined in {PortSearch} and {PkgSearch}
# modules. These methods return records as a search result and a single
# record is encapsulated in either a {PortRecord} or {PkgRecord} object. This
# class is a base class for both.
#
# Basically a Record object is a `{field => value}` hash. Search methods
# implemented in {PortSearch} and {PkgSearch} modules are configurable such
# that user may select what fields to include in the search results.
# Some fields may be obtained directly from search back-end without any
# additional effort. Some other fields may be added for user's convenience by
# "post-processing" Record obtained form the back-end. The Record class
# has {std_fields} method to tell user what fields are available "for free"
# (without any post-processing) from underlying search method, and
# {default_fields} method to list fields that are retrieved by default. The
# {#amend!} method perform such a post-processing. If a user request fields
# that are not in scope of {std_fields}, the {#amend!} is used to generate the
# extra fields.
#
class Record < ::Hash

  require 'puppet/util/package/ports/functions'
  extend Puppet::Util::Package::Ports::Functions

  # These fields may are obtained from search back-end without additional
  # effort (without {#amend!}).
  # @note The method must be implemented in a subclass.
  # @return [Array]
  #
  def self.std_fields
    raise NotImplementedError, "this method must be implemented in a subclass"
  end

  # These fields are requested from an underlying search method by default
  # (when user does not specify what fields to request).
  #
  # Note that this list may include {std_fields} plus some extra fields
  # generated by {#amend!}.
  # @note The method must be implemented in a subclass.
  # @return [Array]
  #
  def self.default_fields
    raise NotImplementedError, "this method must be implemented in a subclass"
  end

  # Dependencies between fields.
  #
  # If we want {#amend!} to add extra fields to {Record} we must first
  # ensure that certain fields are requested from the back-end search command
  # when searching ports or packages. For example, when searching ports with
  # `make search`, one needs to include `:name` field in the `make search`
  # result in order to determine `:pkgname`, i.e. the search command should be
  # like
  #
  #   `make search -C /usr/ports <filter> display=name,...`
  #
  # The {deps_for_amend} returns a hash which describes these dependencies,
  # for example.
  #
  #     {
  #       :pkgname => [:name],      # :pkgname depends on :name
  #       :portorigin => [:path]    # :portorigin depends on :path
  #       ...
  #     }
  #
  # @note The method must be implemented in a subclass.
  # @return [Hash]
  #
  def self.deps_for_amend
    raise NotImplementedError, "this method must be implemented in a subclass"
  end

  # Equivalent to `record.dup.amend!(fields)`.
  #
  # See documentation of {#amend!}.
  # @return [Record]
  #
  def amend(fields)
    self.dup.amend!(fields)
  end

  # Determine what fields should be requested from back-end search method in
  # order to be able to generate (with {#amend!}) all the fields listed in
  # `fields`.
  #
  # This methods makes effective use of {deps_for_amend}.
  #
  # @param fields [Array] an array of fields requested by user,
  # @param key [Symbol] key parameter as passed to `make search` command (used
  #   only by port search),
  #
  # @return [Array]
  #
  def self.determine_search_fields(fields,key=nil)
    search_fields = fields & std_fields
    deps_for_amend.each do |field,deps|
      search_fields += deps if fields.include?(field)
    end
    search_fields << key unless key.nil? or search_fields.include?(key)
    search_fields.uniq!
    search_fields
  end

  # Refine the PortRecord such that it contains specified fields.
  #
  # @param fields [Array] list of field names to include in output
  # @return [Record] self
  #
  def amend!(fields)
    # For internal use.
    def if_wants(fields,what,&block);
      block.call() if fields.include?(what)
    end
    # For internal use.
    def if_wants_one_of(fields,what,&block)
      block.call() if not (fields & what).empty?
    end
    if self[:portname] and self[:portorigin]
      if_wants_one_of(fields,[:options_files,:options_file,:options]) do
        self[:options_files] = self.class.options_files(self[:portname],self[:portorigin])
        if_wants(fields,:options_file) do
          self[:options_file] = self[:options_files].last
        end
        if_wants(fields,:options) do
          self[:options] = Options.load(self[:options_files])
        end
      end
    end
    # filter-out fields not requested by caller
    self.delete_if{|f,r| not fields.include?(f)} unless fields.equal?(:all)
    self
  end

end
end
