require 'puppet/util/package'

module Puppet::Util::Package::Ports

class Record < ::Hash

  require 'puppet/util/package/ports/functions'
  extend Puppet::Util::Package::Ports::Functions

  # These fields may are obtained from search method without doing {#amend}.
  def self.std_fields
    raise NotImplementedError, "this method must be implemented in a subclass"
  end

  # Default set of fields requested from an underlying search method.
  def self.default_fields
    raise NotImplementedError, "this method must be implemented in a subclass"
  end


  # This method must be overwritten in a subclass class.
  #
  # If we want {#amend!} to add extra fields to {Record} we must first
  # ensure that we request certain fields from the backend search command.
  # For example, when searching ports with `make search`, one needs to include
  # `:name` field in the `make search` result in order to determine
  # `:pkgname`, i.e. the search command should be like
  #
  #   `make search -C /usr/ports <filter> display=name,...`
  #
  # The {deps_for_amend} returns a hash which describes these dependencies,
  # for example.
  #
  #     {
  #       :pkgname => [:name],
  #       :portorigin => [:path]
  #       ...
  #     }
  #
  def self.deps_for_amend
    raise NotImplementedError, "this method must be implemented in a subclass"
  end

  # Equivalent to `record.dup.amend!(fields)`.
  #
  # See documentation of {#amend!}.
  def amend(fields)
    self.dup.amend!(fields)
  end

  # Determine what fields should be requested from backend search method in
  # order to be able to create (with {#amend}) all the Record's fields
  # listed in `fields`.
  #
  # This methods makes effective use of {deps_for_amend}.
  #
  # @param fields [Array] an array of fields requested by user,
  # @param key [Symbol] key parameter as passed to `make search` command (used
  #   only by port search),
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
  # @return self
  def amend!(fields)
    def if_wants(fields,what,&block);
      block.call() if fields.include?(what)
    end
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
