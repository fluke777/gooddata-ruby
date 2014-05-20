# encoding: UTF-8

require_relative 'metadata'
require 'pmap'

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
        vars.map do |a|
          data = GoodData.get(a['link'])
          GoodData::UserFilter.new(
            "expression" => data['userFilter']['content']['expression'],
            "level"=> :user,
            "type" => :filter
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

    def self.maqlify_filters(result, options = {})
      only_existing_users = options[:only_existing_users] || true

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

      result.map do |filter|
        # fail "User could"
        login = filter[:login]
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
            "related" => users_lookup[login].uri,
            "level"=> :user,
            "expression" => expression,
            "type" => :filter
          })
      end
    end

    def self.resolve_variable_user_fiters(user_filters, var)
      vals = var.user_values
      project_vals_lookup = vals.reduce({}) do |a, e|
        a[e.related_uri] = e
        a
      end

      to_update = []
      to_delete = []
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
      [to_create, to_delete, to_update]
    end

    def self.execute_variables(filters, var, options = {})
      dry_run = options[:dry_run]
      user_filters = maqlify_filters(filters, :only_existing_users => true)
      to_create, to_delete, to_update = resolve_variable_user_fiters(user_filters, var)

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

    def self.resolve_mandatory_user_fiters(filters)
      
    end

    def self.execute_mufs(filters, name)
      user_filters = maqlify_filters(filters, :only_existing_users => false)
      to_create, to_delete, to_update = resolve_mandatory_user_fiters(user_filters)
      # binding.pry
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
  GoodData.logging_on
  var = GoodData::Variable.all[1]
  x = "login,division,age\nsvarovsky@gooddata.com,hr,14\nsvarovsky@gooddata.com,\"rnd, eng\",19\n"
  filters = GoodData::UserFilterBuilder::get_filters(x, {
    :type => :filter,
    :labels => [
      {:label => {:uri => "/gdc/md/j5wt8v2tl077r21r568l19vx16pq2qal/obj/25"}, :column => 'division'}
    ]
  })
  binding.pry
  GoodData::UserFilterBuilder.execute_mufs(filters, "some var")
end

class Hash
  def slice(*keys)
    keys.map! { |key| convert_key(key) } if respond_to?(:convert_key, true)
    keys.each_with_object(self.class.new) { |k, hash| hash[k] = self[k] if has_key?(k) }
  end
end