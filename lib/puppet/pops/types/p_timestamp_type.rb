module Puppet::Pops
module Types
  class PTimestampType < PAbstractTimeDataType
    def self.register_ptype(loader, ir)
      create_ptype(loader, ir, 'ScalarType',
        'from' => { KEY_TYPE => PTimestampType::DEFAULT, KEY_VALUE => :default },
        'to' => { KEY_TYPE => PTimestampType::DEFAULT, KEY_VALUE => :default }
      )
    end

    def self.new_function(_, loader)
      @new_function ||= Puppet::Functions.create_loaded_function(:new_timestamp, loader) do
        local_types do
          type 'Formats = Variant[String[2],Array[String[2]], 1]'
        end

        dispatch :now do
        end

        dispatch :from_seconds do
          param 'Variant[Integer,Float]', :seconds
        end

        dispatch :from_string do
          param           'String[1]', :string
          optional_param  'Formats', :format
        end

        dispatch :from_string_hash do
          param <<-TYPE, :hash_arg
            Struct[{
              string => String[1],
              Optional[format] => Formats
            }]
          TYPE
        end

        def now
          Time::Timestamp.now
        end

        def from_string(string, format = Time::Timestamp::DEFAULT_FORMATS)
          Time::Timestamp.parse(string, format)
        end

        def from_string_hash(args_hash)
          Time::Timestamp.from_hash(args_hash)
        end

        def from_seconds(seconds)
          Time::Timestamp.new((seconds * Time::NSECS_PER_SEC).to_i)
        end
      end
    end

    def generalize
      DEFAULT
    end

    def impl_class
      Time::Timestamp
    end

    DEFAULT = PTimestampType.new(nil, nil)
  end
end
end
