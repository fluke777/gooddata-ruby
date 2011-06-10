require 'gooddata/models/metadata'

module GoodData
  class Report < GoodData::MdObject 

    class << self
      def [](id)
        if id == :all
          GoodData.get(GoodData.project.md['query'] + '/reports/')['query']['entries']
        else 
          super
        end
      end
    end

    def execute
      puts "Executing report #{uri}"
      result = GoodData.post '/gdc/xtab2/executor3', {"report_req" => {"report" => uri}}
      dataResultUri = result["reportResult2"]["content"]["dataResult"]

      begin
        result = ReportDataResult.new(GoodData.get dataResultUri)
      rescue JSON::ParserError
        sleep 10
        retry
      end
      result
    end

  end
end