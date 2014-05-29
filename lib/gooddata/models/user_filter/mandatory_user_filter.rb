module GoodData

  class MandatoryUserFilter < UserFilter
    class << self
      def [](id, options = {})
        if id == :all
          all(options)
        else
          super
        end
      end

      def all(options={})
        vars = GoodData.get(GoodData.project.md['query'] + '/userfilters/')['query']['entries']

        count = 10000
        offset = 0
        user_lookup = {}
        loop do
          result = GoodData.get("/gdc/md/#{GoodData.project.pid}/userfilters?count=1000&offset=#{offset}")
          result["userFilters"]["items"].each do |item|
            item["userFilters"].each do |f|
              user_lookup[f] = item["user"]
            end
          end
          break if result["userFilters"]["length"] < offset
          offset += count
        end
        vars.map do |a|
          uri = a['link']
          data = GoodData.get(uri)
          GoodData::MandatoryUserFilter.new(
            "expression" => data['userFilter']['content']['expression'],
            "related" => user_lookup[a['link']],
            "level" => :user,
            "type"  => :filter,
            "uri"   => a['link']
          )
        end
      end
    end

    # Creates or updates the mandatory user filter on the server
    #
    # @return [GoodData::MandatoryUserFilter]
    def save
      data = {
        "userFilter" => {
        "content" => {
          "expression" => expression
          },
          "meta" => {
            "category" => "userFilter",
            "title" => related_uri
            }
          }
      }
      res = GoodData.post(GoodData.project.md['obj'], data)
      @json['uri'] = res['uri']
    end    
  end
end
