module GoodData

  class VariableUserFilter < UserFilter
    # Creates or updates the variable user filter on the server
    #
    # @return [String]
    def save
      res = GoodData.post(uri, { :variable => @json })
      @json['uri'] = res['uri']
      self
    end
  end
end
