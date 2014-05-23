# encoding: UTF-8

require_relative 'metadata'

module GoodData
  class UserFilter

    def initialize(data)
      @dirty = false
      @json = data
    end

    def related_uri
      @json['related']
    end

    def related
      uri = related_uri
      level == :project ? GoodData::Project[uri] : GoodData::Profile.new(GoodData.get(uri))
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

    def expression=(expr)
      @dirty = true
      @json['expression'] = expr
    end

    def uri
      @json['uri']
    end

    def pretty_expression
      SmallGoodZilla.pretty_print(expression)
    end

    def to_hash
      @json
    end

    def delete
      GoodData.delete(uri)
    end

    def save
      GoodData.post(uri, { :variable => @json })
    end

  end

  class MandatoryUserFilter < MdObject
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
          result["userFilters"]["items"].each { |item| user_lookup[item["userFilters"].first] = item["user"] }
          break if result["userFilters"]["length"] < offset
          offset += count
        end

        vars.map do |a|
          uri = a['link']
          data = GoodData.get(uri)
          GoodData::UserFilter.new(
            "expression" => data['userFilter']['content']['expression'],
            "related" => user_lookup[a['link']],
            "level" => :user,
            "type"  => :filter,
            "uri"   => a['link']
          )
        end
      end
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

    def find_values(*context)
      uris = context.map { |obj| obj.respond_to?(:uri) ? obj.uri : obj }
      x = {
          "variablesSearch" => {
              "variables" => [
                  uri
              ],
              "context" => uris
          }
      }
      data = GoodData.post("/gdc/md/#{project.pid}/variables/search", x)

      data["variables"].map do |var|
        UserFilter.new(var)
      end
    end

    def project_values
      find_values.select { |v| v.level == :project }
    end

    def user_values
      find_values.select { |v| v.level == :user }
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
      binding.pry
      UserFilterBuilder.reduce_results(values)
    end

    def self.get_values(file, options)
      type = options[:type]
      labels = options[:labels]

      if labels.size == 1 && labels.first.key?(:column) == false
        read_line_wise(file, options)
      else
        read_column_wise(file, options)
      end
    end

    def self.read_column_wise(file, options={})
      labels = options[:labels]
      memo = {}

      CSV.foreach(file, :headers => true, :return_headers => false) do |e|
        login = e[0]
        labels.each do |label|
          column = label[:column]
          values = [e[column]]
          next if values.compact.empty?
          memo[login] = [] unless memo.key?(login)
          memo[login] << {
            :label => label[:label],
            :values => values,
            :over => label[:over],
            :to => label[:to]
          }
        end
      end
      memo
    end

    def self.read_line_wise(file, options={})
      label = options[:labels].first
      memo = {}

      CSV.foreach(file, :headers => false, :return_headers => false) do |e|
        login = e.first
        values = e[1..-1]
        memo[login] = [] unless memo.key?(login)
        memo[login] << {
          :label => label[:label],
          :values => values,
          :over => label[:over],
          :to => label[:to]
        }
      end
      memo
    end

    def self.reduce_results(data)
      data.map {|k, v| {:login => k, :filters => UserFilterBuilder.collect_labels(v)}} 
    end

    def self.collect_labels(data)
      data.group_by {|x| [x[:label], x[:over], x[:to]]}.map {|l, v| {:label => l[0], :over => l[1], :to => l[2], :values => UserFilterBuilder.collect_values(v)}}
    end

    def self.collect_values(data)
      data.reduce([]) do |a, e|
        a.concat(e[:values])
      end
    end

    def self.maqlify_filters(result, options = {})

      only_existing_users = options[:only_existing_users] == false ? false : true

      users_lookup = GoodData.project.users.reduce({}) do |a, e|
        a[e.login] = e
        a
      end
      if only_existing_users
        result.each do |filter|
          login = filter[:login]
          fail "User #{login} is not part of the project and variable #{filter} cannot be resolved" unless users_lookup.key?(login)
        end
      end

      # attribtues_cache = result.reduce({}) do |a, e|
      #   e[:filters].map do |label|
      #     a[label[:over]] = GoodData::Attribute[label[:over]] unless a.key?(label[:over])
      #     a[label[:to]] = GoodData::Attribute[label[:to]] unless a.key?(label[:to])
      #   end
      #   a
      # end

      labels_cache = result.reduce({}) do |a, e|
        e[:filters].map do |label|
          a[label[:label][:uri]] = GoodData::DisplayForm[label[:label][:uri]] unless a.key?(label[:label][:uri])
        end
        a
      end
      small_labels = labels_cache.values.find_all {|label| label.values_count < 100000}
      cache = small_labels.reduce({}) do |a, e|
        lookup = e.values(:limit => 1000000).reduce({}) do |a1, e1|
          a1[e1[:value]] = e1[:uri]
          a1
        end
        a[e.uri] = lookup
        a
      end

      errors = []
      results = result.map do |filter|
        # fail "User could"
        login = filter[:login]
        filters = filter[:filters]
        expressions = filters.map do |filter|
          values = filter[:values]
          label = labels_cache[filter[:label][:uri]]
          element_uris = values.map do |v|
            begin
              if cache.key?(label.uri)
                if cache[label.uri].key?(v)
                  cache[label.uri][v]
                else
                  fail
                end
              else
                label.find_value_uri(v)
              end
            rescue
              errors << [label, v]
              ""
            end
          end
          if filter[:over] && filter[:to]
            "[#{label.attribute_uri}] IN (#{ element_uris.map { |e| '[' + e + ']' }.join(', ') }) OVER [#{filter[:over]}] TO [#{filter[:to]}]"
          else
            "[#{label.attribute_uri}] IN (#{ element_uris.map { |e| '[' + e + ']' }.join(', ') })"
          end
        end
        expression = expressions.join(' AND ')

        GoodData::UserFilter.new(
          {
            "related" => users_lookup[login].uri,
            "level"=> :user,
            "expression" => expression,
            "type" => :filter
          })
      end
      binding.pry
      fail errors unless errors.empty?
      results
    end

    def self.resolve_variable_user_fiters(user_filters, vals)
      project_vals_lookup = vals.reduce({}) do |a, e|
        a[e.related_uri] = e
        a
      end

      user_vals_lookup = user_filters.reduce({}) do |a, e|
        a[e.related_uri] = e
        a
      end

      to_update = []
      to_create = []

      user_filters.each do |val|
        user_uri = val.related_uri
        if project_vals_lookup.key?(user_uri)
          project_val = project_vals_lookup[user_uri]
          if val.expression != project_val.expression
            project_val.expression = val.expression
            to_update << project_val
          end
        else
          to_create << val
        end
      end

      to_delete = vals.reduce([]) do |a, e|
        user_uri = e.related_uri
        unless user_vals_lookup.key?(user_uri)
          a << e
        end
        a
      end

      [to_create, to_delete, to_update]
    end

    def self.execute_variables(filters, var, options = {})
      dry_run = options[:dry_run]
      filters = normalize_filters(filters)
      user_filters = maqlify_filters(filters, :only_existing_users => true)
      to_create, to_delete, to_update = resolve_variable_user_fiters(user_filters, var.user_values)

      return [to_create, to_delete, to_update] if dry_run
      to_delete.each &:delete
      data = to_create.map(&:to_hash).map { |var_val| var_val.merge({:prompt => var.uri })}
      data.each_slice(200) do |slice|
        GoodData.post("/gdc/md/#{GoodData.project.obj_id}/variables/user", ({:variables => slice}))
      end
      to_update.each do |value|
        value.save
      end
      
      [to_create, to_delete, to_update]
    end

    def self.normalize_filters(filters)
      filters.map do |filter|
        if filter.is_a?(Hash)
          filter
        else
          {
            :login => filter.first,
            :filters => [
              {
                :label => {
                  :uri => filter[1]
                },
                :values => filter[2..-1]
              }
            ]
          }
        end
      end
    end

    def self.execute_mufs(filters, options={})
      dry_run = options[:dry_run]
      filters = normalize_filters(filters)
      user_filters = maqlify_filters(filters, :only_existing_users => false)
      to_create, to_delete, to_update = resolve_variable_user_fiters(user_filters, MandatoryUserFilter.all)

      return [to_create, to_delete, to_update] if dry_run
      to_create.each do |var|
        result = GoodData.post("/gdc/md/#{GoodData.project.pid}/obj", {
            "userFilter" => {
                "content" => {
                    "expression" => var.expression
                },
                "meta" => {
                    "category" => "userFilter",
                    "title" => var.expression
                }
            }
        })
      
        GoodData.post("/gdc/md/#{GoodData.project.pid}/userfilters", { 
          "userFilters" => {
                "items" => [
                    {
                        "user" => var.related_uri,
                        "userFilters" => [
                            uri = result["uri"]
                        ]
                    }
                ]
            }
        })
      end
      to_delete.each { |filter| filter.delete }
      to_update.each do |filter|
        GoodData.post(filter.uri, {
            "userFilter" => {
                "content" => {
                    "expression" => filter.expression
                },
                "meta" => {
                    "category" => "userFilter",
                    "title" => filter.expression
                }
            }
        })
      end
      [to_create, to_delete, to_update]
    end
  end
end

def example
  GoodData.logging_on
  var = GoodData::Variable.all[1];
  label = GoodData::DisplayForm["/gdc/md/8z2c3wx15novcptlafq908aylaxqz468/obj/13"];
  filters = GoodData::UserFilterBuilder::get_filters('portfolioCompanies.csv', {
    :type => :filter,
    :labels => [
      {:label => {:uri => "/gdc/md/8z2c3wx15novcptlafq908aylaxqz468/obj/13"}, :to => "/gdc/md/8z2c3wx15novcptlafq908aylaxqz468/obj/13", :over => "/gdc/md/8z2c3wx15novcptlafq908aylaxqz468/obj/13" }
    ]
  });
  GoodData::UserFilterBuilder.execute_variables(filters, var, :dry_run => true)
end

def muf_example
  GoodData.logging_on
  # x = "login,division,age\nsvarovsky@gooddata.com,\"1\",20\n"
  # x = "login,division,age\nsvarovsky@gooddata.com,\"2\",20\n"
  # x = "login,division,age\n"
  # filters = GoodData::UserFilterBuilder::get_filters(x, {
  #   :type => :filter,
  #   :labels => [
  #     {:label => {:uri => "/gdc/md/om15m97we27svj0t6csvaggwlnn8qwwj/obj/199"}, :column => 'division'}
  #   ]
  # })
  # GoodData::UserFilterBuilder.execute_mufs(filters, :dry_run => true)
  
  label = GoodData::Attribute.find_first_by_title('Dev').label_by_name('Id')
  filters = [
    ["svarovsky@gooddata.com", label.uri, "1", "3"]
  ]
  GoodData::UserFilterBuilder.execute_mufs(filters)
  
end

class Hash
  def slice(*keys)
    keys.map! { |key| convert_key(key) } if respond_to?(:convert_key, true)
    keys.each_with_object(self.class.new) { |k, hash| hash[k] = self[k] if has_key?(k) }
  end
end