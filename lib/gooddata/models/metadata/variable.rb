# encoding: UTF-8

require_relative 'metadata'

module GoodData
  class UserFilter

    def initialize(data)
      @json = data
    end

    def related
      uri = @json['related']
      level == :project ? GoodData::Project[uri] : GoodData::AccountSettings.new(GoodData.get(uri))
    end

    def variable
      uri = @json['prompt']
      GoodData::Variable[uri]
    end

    def level
      @json['level'].to_sym
    end

    def type
      @json['type'].to_sym
    end
    

    def expression
      @json['expression']
    end

    def pretty_expression
      SmallGoodZilla.pretty_print(expression)
    end
  end

  class Variable < MdObject
    root_key :prompt

    class << self
      def [](id, options = {})
        if id == :all
          all(options)
        else
          super
        end
      end

      def all(options={})
        vars = GoodData.get(GoodData.project.md['query'] + '/prompts/')['query']['entries']
        vars.map { |a| Variable[a['link']] }
      end
    end

    def values
      x = {
          "variablesSearch" => {
              "variables" => [
                  uri
              ],
              "context" => []
          }
      }
      data = GoodData.post("/gdc/md/#{project.pid}/variables/search", x)

      data["variables"].map do |var|
        UserFilter.new(var)
      end
    end

    def project_values
      values.select { |v| v.level == :project }
    end

    def user_values
      values.select { |v| v.level == :user }
    end

    def type
      content['type'].to_sym
    end

    def attribute
      GoodData::Attribute[content['attribute']]
    end
  end
end


module GoodData
  module UserFilterBuilder

    def self.get_filters(file, options={})
      values = get_values(file, options)
      UserFilterBuilder.reduce_results(values)
    end

    def self.get_values(file, options)
      type = options[:type]
      labels = options[:labels]

      results = if labels.size == 1 && labels.first.key?(:column) == false
        read_line_wise(file, options)
      else
        read_column_wise(file, options)
      end
    end

    def self.read_column_wise(file, options={})
      labels = options[:labels]
      memo = {}

      CSV.parse(file, :headers => true) do |e|
        login = e[0]
        labels.each do |label|
          column = label[:column]
          values = [e[column]]
          next if values.compact.empty?
          memo[login] = [] unless memo.key?(login)
          memo[login] << {
            :label => label[:label],
            :values => values
          }
        end
      end
      memo
    end

    def self.read_line_wise(file, options={})
      label = options[:labels].first
      memo = {}

      CSV.parse(file) do |e|
        login = e.first
        values = e[1..-1]
        memo[login] = [] unless memo.key?(login)
        memo[login] << {
          :label => label[:label],
          :values => values
        }
      end
      memo
    end

    def self.reduce_results(data)
      data.map {|k, v| {:login => k, :filters => UserFilterBuilder.collect_labels(v)}} 
    end

    def self.collect_labels(data)
      data.group_by {|x| x[:label]}.map {|l, v| {:label => l, :values => UserFilterBuilder.collect_values(v)}}
    end

    def self.collect_values(data)
      data.reduce([]) do |a, e|
        a.concat(e[:values])
      end
    end

    # - filters resolve
    # - if unable to resolve fail
    # - if able to resolve move on
    # - find those that are new or in need of update
    # - optional reset those not mentioned 
    # - update
  end
end


def example
  x = "login,country,age\nsvarovsky@gooddata.com,Tomas,14\nsvarovsky@gooddata.com,Petr,19\nsvarovsky@gooddata.com,Tomas,30"
  result = GoodData::UserFilterBuilder::get_filters(x, {
    :type => :filter,
    :labels => [
      {:label => {:uri => "/gdc/md/j5wt8v2tl077r21r568l19vx16pq2qal/obj/27"}, :column => 'country'}
    ]
  })

  # result.[
  #   {
  #     :login=>"tomas@gooddata.com",
  #     :filters=> [
  #       {:label=>{:uri=>"label/34"}, :values=>["US"]},
  #       {:label=>{:uri=>"label/99"}, :values=>["14"]}
  #     ]
  #   },
  #   {
  #     :login=>"petr@gooddata.com",
  #     :filters => [
  #       {:label=>{:uri=>"label/34"}, :values=>["US", "KZ"]},
  #       {:label=>{:uri=>"label/99"}, :values=>["19", "30"]}
  #     ]
  #   }
  # ]

  users_lookup = GoodData.project.users.reduce({}) do |a, e|
    a[e.login] = e
    a
  end

  var_values = result.map do |filter|
    # fail "User could"
    login = filter[:login]
    fail "User #{login} is not part of the project and variable cannot be resolved" unless users_lookup.key?(login)
    related_uri = users_lookup[login].uri

    filters = filter[:filters]
    expressions = filters.map do |filter|
      values = filter[:values]
      label = GoodData::DisplayForm[filter[:label][:uri]]
      element_uris = values.map {|v| label.find_value_uri(v)}
      "[#{label.attribute.uri}] IN (#{ element_uris.map { |e| '[' + e + ']' }.join(', ') })"
    end

    expression = expressions.join(' AND ')

    GoodData::UserFilter.new(
      {
        "related" => related_uri,
        "level"=> :user,
        "expression" => expression,
        "type" => :filter
      })
  end
  
  var = GoodData::Variable.all[1]
  vals = var.user_values
  binding.pry
end
