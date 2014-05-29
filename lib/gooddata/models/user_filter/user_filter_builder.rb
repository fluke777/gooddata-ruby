# encoding: UTF-8

require_relative 'metadata'

module GoodData
  module UserFilterBuilder

    def self.get_filters(file, options={})
      values = get_values(file, options)
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
      index = options[:user_column] || 0
      CSV.foreach(file, :headers => true, :return_headers => false) do |e|
        login = e[index]
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
      data.mapcat do |e|
        e[:values]
      end
    end

    def self.create_cache(data, key)
      data.reduce({}) do |a, e|
        a[e.send(key)] = e
        a
      end
    end

    def self.verify_existing_users(filters, options = {})
      users_must_exist = options[:users_must_exist] == false ? false : true
      users_cache = options[:users_cache] || create_cache(GoodData.project.users, :login)
      if users_must_exist
        missing_users_filter = filters.find_all do |filter|
          login = filter[:login]
          !users_cache.key?(login)
        end
        fail "Users #{missing_users_filter.count} are not part of the project and variable cannot be resolved since :users_must_exist is set to true" unless missing_users_filter.empty?
      end      
    end

    def self.create_label_cache(result)
      result.reduce({}) do |a, e|
        e[:filters].map do |filter|
          a[filter[:label]] = GoodData::Label[filter[:label]] unless a.key?(filter[:label])
        end
        a
      end
    end

    def self.create_lookups_cache(small_labels)
      small_labels.reduce({}) do |a, e|
        lookup = e.values(:limit => 1000000).reduce({}) do |a1, e1|
          a1[e1[:value]] = e1[:uri]
          a1
        end
        a[e.uri] = lookup
        a
      end
    end

    def self.get_small_labels(labels_cache)
      labels_cache.values.find_all {|label| label.values_count < 100000}
    end

    def self.create_expression(filter, labels_cache, lookups_cache)
      errors = []
      values = filter[:values]
      label = labels_cache[filter[:label]]
      element_uris = values.map do |v|
        begin
          if lookups_cache.key?(label.uri)
            if lookups_cache[label.uri].key?(v)
              lookups_cache[label.uri][v]
            else
              fail
            end
          else
            label.find_value_uri(v)
          end
        rescue
          errors << [label, v]
          nil
        end
      end
      
      expression = if element_uris.empty?
        "TRUE"
      elsif filter[:over] && filter[:to]
        "([#{label.attribute_uri}] IN (#{ element_uris.compact.sort.map { |e| '[' + e + ']' }.join(', ') })) OVER [#{filter[:over]}] TO [#{filter[:to]}]"
      else
        "[#{label.attribute_uri}] IN (#{ element_uris.compact.sort.map { |e| '[' + e + ']' }.join(', ') })"
      end
      [expression, errors]
    end

    def self.create_filter(expression, related)
      {
        "related" => related,
        "level" => :user,
        "expression" => expression,
        "type" => :filter
      }
    end

    def self.maqlify_filters(result, options = {})
      users_cache = options[:users_cache] || create_cache(GoodData.project.users, :login)
      labels_cache = create_label_cache(result)
      small_labels = get_small_labels(labels_cache)
      lookups_cache = create_lookups_cache(small_labels)

      errors = []
      results = result.mapcat do |filter|
        login = filter[:login]
        expressions = filter[:filters].map do |filter|
          expression, error = create_expression(filter, labels_cache, lookups_cache)
          errors << error unless error.empty?
          create_filter(expression, (users_cache[login] && users_cache[login].uri))
        end
      end
      [results, errors]
    end

    def self.resolve_user_filter(user = [], project = [])
      user ||= []
      project ||= []
      to_create = user - project
      to_delete = project - user
      {:create => to_create, :delete => to_delete}
    end

    def self.resolve_variable_user_fiters(user_filters, vals)
      project_vals_lookup = vals.group_by {|x| x.related_uri}
      user_vals_lookup = user_filters.group_by {|x| x.related_uri}

      a = vals.map {|x| [x.related_uri, x]}
      b = user_filters.map {|x| [x.related_uri, x] }

      users_to_try = a.map {|x| x.first}.concat(b.map {|x| x.first}).uniq
      results = users_to_try.map do |user|        
        resolve_user_filter(user_vals_lookup[user], project_vals_lookup[user])
      end

      to_create = results.map {|x| x[:create]}.flatten.group_by {|x| x.related_uri}
      to_delete = results.map {|x| x[:delete]}.flatten.group_by {|x| x.related_uri}
      [to_create, to_delete]
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
                :label => filter[1],
                :values => filter[2..-1]
              }
            ]
          }
        end
      end
    end

    def self.execute(user_filters, project_filters, klass, options = {})
      ignore_missing_values = options[:ignore_missing_values]
      users_must_exist = options[:users_must_exist] == false ? false : true
      filters = normalize_filters(user_filters)
      domain = options[:domain]
      
      users = domain ? GoodData.project.users + domain.users : GoodData.project.users
      users_cache = create_cache(users , :login)
      verify_existing_users(filters, :users_must_exist => users_must_exist, :users_cache => users_cache)
      user_filters, errors = maqlify_filters(filters, options.merge({ :users_cache => users_cache }))
      fail "Validation failed" if !ignore_missing_values && !errors.empty? 

      filters = user_filters.map { |data| klass.new(data) }
      resolve_variable_user_fiters(filters, project_filters)
    end

    def self.execute_variables(filters, var, options = {})
      dry_run = options[:dry_run]
      to_create, to_delete = execute(filters, var.user_values, VariableUserFilter, options)
      return [to_create, to_delete] if dry_run

      to_delete.each { |related_uri, group| group.each &:delete }
      data = to_create.values.flatten.map(&:to_hash).map { |var_val| var_val.merge({:prompt => var.uri })}
      data.each_slice(200) do |slice|
        GoodData.post("/gdc/md/#{GoodData.project.obj_id}/variables/user", ({:variables => slice}))
      end
      [to_create, to_delete]
    end

    def self.execute_mufs(filters, options={})
      dry_run = options[:dry_run]
      to_create, to_delete = execute(filters, MandatoryUserFilter.all, MandatoryUserFilter, options)
      return [to_create, to_delete] if dry_run

      to_create.each_pair do |related_uri, group|        
        group.each do |filter|
          filter.save
        end

        res = GoodData.get("/gdc/md/#{GoodData.project.pid}/userfilters?users=#{related_uri}")
        items = res['userFilters']['items'].empty? ? [] : res['userFilters']['items'].first['userFilters']

        GoodData.post("/gdc/md/#{GoodData.project.pid}/userfilters", { 
          "userFilters" => {
            "items" => [{
              "user" => related_uri,
              "userFilters" => items.concat(group.map {|filter| filter.uri})
            }]
          }
        })
      end
      to_delete.each do |related_uri, group|
        if related_uri
          res = GoodData.get("/gdc/md/#{GoodData.project.pid}/userfilters?users=#{related_uri}")
          items = res['userFilters']['items'].empty? ? [] : res['userFilters']['items'].first['userFilters']
          GoodData.post("/gdc/md/#{GoodData.project.pid}/userfilters", { 
            "userFilters" => {
              "items" => [{
                "user" => related_uri,
                "userFilters" => items - group.map(&:uri)
              }]
            }
          })
        end
        group.each do |filter|
          filter.delete
        end
      end
      [to_create, to_delete]
    end
  end
end
