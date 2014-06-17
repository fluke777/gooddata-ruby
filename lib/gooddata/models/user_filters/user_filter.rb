# encoding: UTF-8

module GoodData

  class UserFilter

    def initialize(data)
      @dirty = false
      @json = data
    end

    def ==(o)
      o.class == self.class && o.related_uri == related_uri && o.expression == expression
    end
    alias_method :eql?, :==

    def hash
      [related_uri, expression].hash
    end

    # Returns the uri of the object this filter is related to. It can be either project or a user
    #
    # @return [String] Uri of related object
    def related_uri
      @json['related']
    end

    # Returns the the object of this filter is related to. It can be either project or a user
    #
    # @return [GoodData::Project | GoodData::Profile] Related object
    def related
      uri = related_uri
      level == :project ? GoodData::Project[uri] : GoodData::Profile.new(GoodData.get(uri))
    end

    # Returns the the object of this filter is related to. It can be either project or a user
    #
    # @return [GoodData::Project | GoodData::Profile] Related object
    def variable
      uri = @json['prompt']
      GoodData::Variable[uri]
    end

    # Returns the level this filter is applied on. Either project or filter.
    #
    # @return [GoodData::Project | GoodData::Profile] Related object
    def level
      @json['level'].to_sym
    end

    # ????
    #
    # @return [GoodData::Project | GoodData::Profile] Related object
    def type
      @json['type'].to_sym
    end

    # Returns the MAQL expression of the filter
    #
    # @return [String] MAQL expression
    def expression
      @json['expression']
    end

    # Allows to set the MAQL expression of the filter
    #
    # @param expression [String] MAQL expression
    # @return [String] MAQL expression
    def expression=(expression)
      @dirty = true
      @json['expression'] = expression
    end

    # Gives you URI of the filter
    #
    # @return [String]
    def uri
      @json['uri']
    end

    # Allows to set URI of the filter
    #
    # @return [String]
    def uri=(uri)
      @json['uri'] = uri
    end

    # Returns pretty version of the expression
    #
    # @return [String]
    def pretty_expression
      SmallGoodZilla.pretty_print(expression)
    end

    # Returns hash representation of the filter
    #
    # @return [Hash]
    def to_hash
      @json
    end

    # Deletes the filter from the server
    #
    # @return [String]
    def delete
      GoodData.delete(uri)
    end
  end
end
