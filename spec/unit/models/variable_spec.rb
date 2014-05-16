require 'csv'
require 'variable_uploader'

ROW_BASED_DATA = "tomas@gooddata.com,US,CZ,KZ\npetr@gooddata.com,US\npetr@gooddata.com,KZ"
COLUMN_BASED_DATA_WITH_HEADERS = "login,country,age\ntomas@gooddata.com,US,14\npetr@gooddata.com,US,19\npetr@gooddata.com,KZ,30"
COLUMN_BASED_DATA_WITH_HEADERS_AND_NIL_VAL = "login,country,age\ntomas@gooddata.com,US,14\npetr@gooddata.com,US,19\npetr@gooddata.com,KZ,"
COLUMN_BASED_DATA_WITH_HEADERS_AND_EMPTY_VAL = "login,country,age\ntomas@gooddata.com,US,14\npetr@gooddata.com,US,19\npetr@gooddata.com,KZ,\"\""



describe "DSL" do
  it "should pick the values from row based file" do
    results = GoodData::VariableUploader::get_values(ROW_BASED_DATA, {
      :type => :filter,
      :labels => [{:label => {:uri => "label/34"}}]
    })
    
    results.should == {
      "tomas@gooddata.com"=>[
        {:label=>{:uri=>"label/34"}, :values=>["US", "CZ", "KZ"]}
      ],
     "petr@gooddata.com"=> [
       {:label=>{:uri=>"label/34"}, :values=>["US"]},
       {:label=>{:uri=>"label/34"}, :values=>["KZ"]}
      ]
    }
  end

  it "should pick the values from column based file" do
    results = GoodData::VariableUploader::get_values(COLUMN_BASED_DATA_WITH_HEADERS, {
      :type => :filter,
      :labels => [{:label => {:uri => "label/34"}, :column => 'country'}]
    })
    results.should == {
      "tomas@gooddata.com"=>[
        {:label=>{:uri=>"label/34"}, :values=>["US"]}
      ],
     "petr@gooddata.com"=> [
       {:label=>{:uri=>"label/34"}, :values=>["US"]},
       {:label=>{:uri=>"label/34"}, :values=>["KZ"]}
      ]
    }
  end

  it "should pick the values from column based file with multiple columns" do
    results = GoodData::VariableUploader::get_values(COLUMN_BASED_DATA_WITH_HEADERS, {
      :type => :filter,
      :labels => [{:label => {:uri => "label/34"}, :column => 'country'}, {:label => {:uri => "label/99"}, :column => 'age'}]
    })
    
    results.should == {
      "tomas@gooddata.com"=>[
        {:label=>{:uri=>"label/34"}, :values=>["US"]},
        {:label=>{:uri=>"label/99"}, :values=>["14"]}
      ],
     "petr@gooddata.com"=> [
       {:label=>{:uri=>"label/34"}, :values=>["US"]},
       {:label=>{:uri=>"label/99"}, :values=>["19"]},
       {:label=>{:uri=>"label/34"}, :values=>["KZ"]},
       {:label=>{:uri=>"label/99"}, :values=>["30"]}
      ]
    }
  end

  it "should process end to end" do
    result = GoodData::VariableUploader::get_filters(COLUMN_BASED_DATA_WITH_HEADERS, {
      :type => :filter,
      :labels => [{:label => {:uri => "label/34"}, :column => 'country'}, {:label => {:uri => "label/99"}, :column => 'age'}]
    })
    result.should == [
      {
        :login=>"tomas@gooddata.com",
        :filters=> [
          {:label=>{:uri=>"label/34"}, :values=>["US"]},
          {:label=>{:uri=>"label/99"}, :values=>["14"]}
        ]
      },
      {
        :login=>"petr@gooddata.com",
        :filters => [
          {:label=>{:uri=>"label/34"}, :values=>["US", "KZ"]},
          {:label=>{:uri=>"label/99"}, :values=>["19", "30"]}
        ]
      }
    ]
  end

  it "should process end to end nil value should be ignored" do
    result = GoodData::VariableUploader::get_filters(COLUMN_BASED_DATA_WITH_HEADERS_AND_NIL_VAL, {
      :type => :filter,
      :labels => [{:label => {:uri => "label/34"}, :column => 'country'}, {:label => {:uri => "label/99"}, :column => 'age'}]
    })
    result.should == [
      {
        :login=>"tomas@gooddata.com",
        :filters=> [
          {:label=>{:uri=>"label/34"}, :values=>["US"]},
          {:label=>{:uri=>"label/99"}, :values=>["14"]}
        ]
      },
      {
        :login=>"petr@gooddata.com",
        :filters => [
          {:label=>{:uri=>"label/34"}, :values=>["US", "KZ"]},
          {:label=>{:uri=>"label/99"}, :values=>["19"]}
        ]
      }
    ]
  end

  it "should process end to end nil value should be ignored" do
    result = GoodData::VariableUploader::get_filters(COLUMN_BASED_DATA_WITH_HEADERS_AND_EMPTY_VAL, {
      :type => :filter,
      :labels => [{:label => {:uri => "label/34"}, :column => 'country'}, {:label => {:uri => "label/99"}, :column => 'age'}]
    })
    result.should == [
      {
        :login=>"tomas@gooddata.com",
        :filters=> [
          {:label=>{:uri=>"label/34"}, :values=>["US"]},
          {:label=>{:uri=>"label/99"}, :values=>["14"]}
        ]
      },
      {
        :login=>"petr@gooddata.com",
        :filters => [
          {:label=>{:uri=>"label/34"}, :values=>["US", "KZ"]},
          {:label=>{:uri=>"label/99"}, :values=>["19", ""]}
        ]
      }
    ]
  end

  it "should collect values for every user" do
    data = {
      "tomas" => [
        {:label=>{:uri=>"label/34"}, :values=>["US"]},
        {:label=>{:uri=>"label/34"}, :values=>["KZ"]},
        {:label=>{:uri=>"label/99"}, :values=>["18"]},
        {:label=>{:uri=>"label/99"}, :values=>["20"]}
      ],
      "petr" => [
        {:label=>{:uri=>"label/34"}, :values=>["US"]},
        {:label=>{:uri=>"label/99"}, :values=>["2"]},
        {:label=>{:uri=>"label/99"}, :values=>["1"]}
      ]
    }
    result = GoodData::VariableUploader.reduce_results(data)
    result.should == [{:login=>"tomas",
      :filters=>
       [{:label=>{:uri=>"label/34"}, :values=>["US", "KZ"]},
        {:label=>{:uri=>"label/99"}, :values=>["18", "20"]}]},
     {:login=>"petr",
      :filters =>
       [{:label=>{:uri=>"label/34"}, :values=>["US"]},
        {:label=>{:uri=>"label/99"}, :values=>["2", "1"]}]}]
  end

  it "should collect values for every label" do
    data = [
      {:label=>{:uri=>"label/34"}, :values=>["US"]},
      {:label=>{:uri=>"label/34"}, :values=>["KZ"]},
      {:label=>{:uri=>"label/99"}, :values=>["18"]},
      {:label=>{:uri=>"label/99"}, :values=>["20"]}
    ]
    result = GoodData::VariableUploader.collect_labels(data)
    result.should == [{:label=>{:uri=>"label/34"}, :values=>["US", "KZ"]},
     {:label=>{:uri=>"label/99"}, :values=>["18", "20"]}]
    
  end

  it "should collect values" do
    data = [
      {:label=>{:uri=>"label/34"}, :values=>["US"]},
      {:label=>{:uri=>"label/34"}, :values=>["KZ"]}
    ]
    results = GoodData::VariableUploader.collect_values(data)
    results.should == ["US", "KZ"]
  end

  it "should translate filters into MAQL filters" do
    data = [
      {
        :login=>"tomas@gooddata.com",
        :filters=> [
          {:label=>{:uri=>"label/34"}, :values=>["US"]},
          {:label=>{:uri=>"label/99"}, :values=>["14"]}
        ]
      },
      {
        :login=>"petr@gooddata.com",
        :filters => [
          {:label=>{:uri=>"label/34"}, :values=>["US", "KZ"]},
          {:label=>{:uri=>"label/99"}, :values=>["19"]}
        ]
      }
    ]
    results = data.map do |user_data|
      {
        :login => user_data[:login],
        :maql_filter => user_data[:filters].map { |item| "[#{item[:label][:uri]}] IN (#{item[:values].join(', ')})" }.join(" AND ")
      }
    end
    results.should == [
      {:login=>"tomas@gooddata.com", :maql_filter=>"[label/34] IN (US) AND [label/99] IN (14)"},
      {:login=>"petr@gooddata.com", :maql_filter=>"[label/34] IN (US, KZ) AND [label/99] IN (19)"}
    ]
  end
end
