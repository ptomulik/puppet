#! /usr/bin/env ruby
require 'spec_helper'
require 'puppet/util/package/ports'
require 'puppet/util/package/ports/functions'
require 'puppet/util/package/ports/port_search'
require 'puppet/util/package/ports/pkg_search'

describe Puppet::Util::Package::Ports do
  it do
    described_class.should include Puppet::Util::Package::Ports::PortSearch
  end
  it do
    described_class.should include Puppet::Util::Package::Ports::PkgSearch
  end
end
