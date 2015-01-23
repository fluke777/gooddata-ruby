# encoding: UTF-8

require_relative '../metadata'

module GoodData
  class Dataset < MdObject
    root_key :dataSet

    class << self
      # Method intended to get all objects of that type in a specified project
      #
      # @param options [Hash] the options hash
      # @option options [Boolean] :full if passed true the subclass can decide to pull in full objects. This is desirable from the usability POV but unfortunately has negative impact on performance so it is not the default
      # @return [Array<GoodData::MdObject> | Array<Hash>] Return the appropriate metadata objects or their representation
      def all(options = { :client => GoodData.connection, :project => GoodData.project })
        query('datasets', Dataset, options)
      end
    end

    def attributes
      attribute_uris.pmap { |a_uri| project.attributes(a_uri) }
    end

    def attribute_uris
      content['attributes']
    end

    def facts
      fact_uris.pmap { |a_uri| project.attributes(a_uri) }
    end

    def fact_uris
      content['facts']
    end

    def date_dimension?
      attributes.all?(&:is_date_attribute?) && fact_uris.empty?
    end
  end
end
