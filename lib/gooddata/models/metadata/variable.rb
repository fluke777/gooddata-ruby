# # encoding: UTF-8
# 
# require_relative 'metadata'
# 
# module GoodData
#   class UserFilter
# 
#     def initialize(data)
#       @dirty = false
#       @json = data
#     end
# 
#     def ==(o)
#       o.class == self.class && o.related_uri == related_uri && o.expression == expression
#     end
#     alias_method :eql?, :==
# 
#     def hash
#       [related_uri, expression].hash
#     end
# 
#     def related_uri
#       @json['related']
#     end
# 
#     def related
#       uri = related_uri
#       level == :project ? GoodData::Project[uri] : GoodData::Profile.new(GoodData.get(uri))
#     end
# 
#     def variable
#       uri = @json['prompt']
#       GoodData::Variable[uri]
#     end
# 
#     def level
#       @json['level'].to_sym
#     end
# 
#     def type
#       @json['type'].to_sym
#     end
# 
#     def expression
#       @json['expression']
#     end
# 
#     def expression=(expr)
#       @dirty = true
#       @json['expression'] = expr
#     end
# 
#     def uri
#       @json['uri']
#     end
# 
#     def uri=(uri)
#       @json['uri'] = uri
#     end
# 
#     def pretty_expression
#       SmallGoodZilla.pretty_print(expression)
#     end
# 
#     def to_hash
#       @json
#     end
# 
#     def delete
#       GoodData.delete(uri)
#     end
# 
#     def save
#       res = GoodData.post(uri, { :variable => @json })
#       @json['uri'] = res['uri']
#       self
#     end
# 
#   end
# 
#   class VariableUserFilter < UserFilter
#   end
# 
#   class MandatoryUserFilter < UserFilter
#     class << self
#       def [](id, options = {})
#         if id == :all
#           all(options)
#         else
#           super
#         end
#       end
# 
#       def all(options={})
#         vars = GoodData.get(GoodData.project.md['query'] + '/userfilters/')['query']['entries']
# 
#         count = 10000
#         offset = 0
#         user_lookup = {}
#         loop do
#           result = GoodData.get("/gdc/md/#{GoodData.project.pid}/userfilters?count=1000&offset=#{offset}")
#           result["userFilters"]["items"].each do |item|
#             item["userFilters"].each do |f|
#               user_lookup[f] = item["user"]
#             end
#           end
#           break if result["userFilters"]["length"] < offset
#           offset += count
#         end
#         vars.map do |a|
#           uri = a['link']
#           data = GoodData.get(uri)
#           GoodData::MandatoryUserFilter.new(
#             "expression" => data['userFilter']['content']['expression'],
#             "related" => user_lookup[a['link']],
#             "level" => :user,
#             "type"  => :filter,
#             "uri"   => a['link']
#           )
#         end
#       end
#     end
#     def save
#       data = {
#         "userFilter" => {
#         "content" => {
#           "expression" => expression
#           },
#           "meta" => {
#             "category" => "userFilter",
#             "title" => related_uri
#             }
#           }
#       }
#       res = GoodData.post(GoodData.project.md['obj'], data)
#       @json['uri'] = res['uri']
#     end    
#   end
# 
#   class Variable < MdObject
#     root_key :prompt
# 
#     class << self
#       def [](id, options = {})
#         if id == :all
#           all(options)
#         else
#           super
#         end
#       end
# 
#       def all(options={})
#         vars = GoodData.get(GoodData.project.md['query'] + '/prompts/')['query']['entries']
#         vars.map { |a| Variable[a['link']] }
#       end
#     end
# 
#     def find_values(*context)
#       uris = context.map { |obj| obj.respond_to?(:uri) ? obj.uri : obj }
#       x = {
#           "variablesSearch" => {
#               "variables" => [
#                   uri
#               ],
#               "context" => uris
#           }
#       }
#       data = GoodData.post("/gdc/md/#{project.pid}/variables/search", x)
# 
#       data["variables"].map do |var|
#         VariableUserFilter.new(var)
#       end
#     end
# 
#     def project_values
#       find_values.select { |v| v.level == :project }
#     end
# 
#     def user_values
#       find_values.select { |v| v.level == :user }
#     end
# 
#     def type
#       content['type'].to_sym
#     end
# 
#     def attribute
#       GoodData::Attribute[content['attribute']]
#     end
#   end
# end
# 
# module GoodData
#   module UserFilterBuilder
# 
#     def self.get_filters(file, options={})
#       values = get_values(file, options)
#       UserFilterBuilder.reduce_results(values)
#     end
# 
#     def self.get_values(file, options)
#       type = options[:type]
#       labels = options[:labels]
# 
#       if labels.size == 1 && labels.first.key?(:column) == false
#         read_line_wise(file, options)
#       else
#         read_column_wise(file, options)
#       end
#     end
# 
#     def self.read_column_wise(file, options={})
#       labels = options[:labels]
#       memo = {}
# 
#       CSV.foreach(file, :headers => true, :return_headers => false) do |e|
#         login = e[0]
#         labels.each do |label|
#           column = label[:column]
#           values = [e[column]]
#           next if values.compact.empty?
#           memo[login] = [] unless memo.key?(login)
#           memo[login] << {
#             :label => label[:label],
#             :values => values,
#             :over => label[:over],
#             :to => label[:to]
#           }
#         end
#       end
#       memo
#     end
# 
#     def self.read_line_wise(file, options={})
#       label = options[:labels].first
#       memo = {}
# 
#       CSV.foreach(file, :headers => false, :return_headers => false) do |e|
#         login = e.first
#         values = e[1..-1]
#         memo[login] = [] unless memo.key?(login)
#         memo[login] << {
#           :label => label[:label],
#           :values => values,
#           :over => label[:over],
#           :to => label[:to]
#         }
#       end
#       memo
#     end
# 
#     def self.reduce_results(data)
#       data.map {|k, v| {:login => k, :filters => UserFilterBuilder.collect_labels(v)}} 
#     end
# 
#     def self.collect_labels(data)
#       data.group_by {|x| [x[:label], x[:over], x[:to]]}.map {|l, v| {:label => l[0], :over => l[1], :to => l[2], :values => UserFilterBuilder.collect_values(v)}}
#     end
# 
#     def self.collect_values(data)
#       data.reduce([]) do |a, e|
#         a.concat(e[:values])
#       end
#     end
# 
#     def self.create_cache(data, key)
#       data.reduce({}) do |a, e|
#         a[e.send(key)] = e
#         a
#       end
#     end
# 
#     def self.verify_existing_users(filters, options = {})
#       users_must_exist = options[:users_must_exist] == false ? false : true
#       users_cache = options[:users_cache] || create_cache(GoodData.project.users, :login)
#       if users_must_exist
#         missing_users_filter = filters.find_all do |filter|
#           login = filter[:login]
#           !users_cache.key?(login)
#         end
#         fail "Users #{missing_users_filter.count} are not part of the project and variable cannot be resolved since :users_must_exist is set to true" unless missing_users_filter.empty?
#       end      
#     end
# 
#     def self.maqlify_filters(result, options = {})
#       users_cache = options[:users_cache] || create_cache(GoodData.project.users, :login)
#       ignore_missing_values = options[:ignore_missing_values]
# 
#       labels_cache = result.reduce({}) do |a, e|
#         e[:filters].map do |label|
#           a[label[:label][:uri]] = GoodData::DisplayForm[label[:label][:uri]] unless a.key?(label[:label][:uri])
#         end
#         a
#       end
# 
#       small_labels = labels_cache.values.find_all {|label| label.values_count < 100000}
#       lookups_cache = small_labels.reduce({}) do |a, e|
#         lookup = e.values(:limit => 1000000).reduce({}) do |a1, e1|
#           a1[e1[:value]] = e1[:uri]
#           a1
#         end
#         a[e.uri] = lookup
#         a
#       end
# 
#       errors = []
#       results = result.reduce([]) do |a, filter|
#         # fail "User could"
#         login = filter[:login]
#         filters = filter[:filters]
#         expressions = filters.map do |filter|
#           values = filter[:values]
#           label = labels_cache[filter[:label][:uri]]
#           element_uris = values.map do |v|
#             begin
#               if lookups_cache.key?(label.uri)
#                 if lookups_cache[label.uri].key?(v)
#                   lookups_cache[label.uri][v]
#                 else
#                   fail
#                 end
#               else
#                 label.find_value_uri(v)
#               end
#             rescue
#               errors << [label, v]
#               nil
#             end
#           end
#           
#           if element_uris.empty?
#             "TRUE"
#           elsif filter[:over] && filter[:to]
#             "([#{label.attribute_uri}] IN (#{ element_uris.compact.sort.map { |e| '[' + e + ']' }.join(', ') })) OVER [#{filter[:over]}] TO [#{filter[:to]}]"
#           else
#             "[#{label.attribute_uri}] IN (#{ element_uris.compact.sort.map { |e| '[' + e + ']' }.join(', ') })"
#           end
#         end
# 
#         expressions.each do |expression|
#           a << {
#               "related" => (users_cache[login] && users_cache[login].uri) || nil,
#               "level" => :user,
#               "expression" => expression,
#               "type" => :filter
#             }
#         end
#         a
#       end
#       fail "Validation failed" if !ignore_missing_values && !errors.empty? 
#       results
#     end
# 
#     def self.resolve_user_filter(user = [], project = [])
#       user ||= []
#       project ||= []
#       to_create = user - project
#       to_delete = project - user
#       {:create => to_create, :delete => to_delete}
#     end
# 
#     def self.resolve_variable_user_fiters(user_filters, vals)
#       project_vals_lookup = vals.group_by {|x| x.related_uri}
#       user_vals_lookup = user_filters.group_by {|x| x.related_uri}
# 
#       a = vals.map {|x| [x.related_uri, x]}
#       b = user_filters.map {|x| [x.related_uri, x] }
# 
#       users_to_try = a.map {|x| x.first}.concat(b.map {|x| x.first}).uniq
#       results = users_to_try.map do |user|        
#         resolve_user_filter(user_vals_lookup[user], project_vals_lookup[user])
#       end
# 
#       to_create = results.map {|x| x[:create]}.flatten.group_by {|x| x.related_uri}
#       to_delete = results.map {|x| x[:delete]}.flatten.group_by {|x| x.related_uri}
#       [to_create, to_delete]
#     end
# 
#     def self.normalize_filters(filters)
#       filters.map do |filter|
#         if filter.is_a?(Hash)
#           filter
#         else
#           {
#             :login => filter.first,
#             :filters => [
#               {
#                 :label => {
#                   :uri => filter[1]
#                 },
#                 :values => filter[2..-1]
#               }
#             ]
#           }
#         end
#       end
#     end
# 
#     def self.execute(user_filters, project_filters, klass, options = {})
#       users_must_exist = options[:users_must_exist] == false ? false : true
#       filters = normalize_filters(user_filters)
#       domain = options[:domain]
#       
#       users = domain ? GoodData.project.users + domain.users : GoodData.project.users
#       users_cache = create_cache(users , :login)
#       verify_existing_users(filters, :users_must_exist => users_must_exist, :users_cache => users_cache)
#       user_filters = maqlify_filters(filters, options.merge({ :users_cache => users_cache }))
#       filters = user_filters.map { |data| klass.new(data) }
#       resolve_variable_user_fiters(filters, project_filters)
#     end
# 
#     def self.execute_variables(filters, var, options = {})
#       dry_run = options[:dry_run]
#       to_create, to_delete = execute(filters, var.user_values, VariableUserFilter, options)
#       return [to_create, to_delete] if dry_run
#       
#       to_delete.each { |related_uri, group| group.each &:delete }
#       data = to_create.values.flatten.map(&:to_hash).map { |var_val| var_val.merge({:prompt => var.uri })}
#       data.each_slice(200) do |slice|
#         GoodData.post("/gdc/md/#{GoodData.project.obj_id}/variables/user", ({:variables => slice}))
#       end
#       [to_create, to_delete]
#     end
# 
#     def self.execute_mufs(filters, options={})
#       dry_run = options[:dry_run]
#       to_create, to_delete = execute(filters, MandatoryUserFilter.all, MandatoryUserFilter, options)
#       return [to_create, to_delete] if dry_run
#       to_create.each_pair do |related_uri, group|
#         
#         group.each do |filter|
#           filter.save
#         end
# 
#         res = GoodData.get("/gdc/md/#{GoodData.project.pid}/userfilters?users=#{related_uri}")
#         items = res['userFilters']['items'].empty? ? [] : res['userFilters']['items'].first['userFilters']
# 
#         GoodData.post("/gdc/md/#{GoodData.project.pid}/userfilters", { 
#           "userFilters" => {
#             "items" => [{
#               "user" => related_uri,
#               "userFilters" => items.concat(group.map {|filter| filter.uri})
#             }]
#           }
#         })
#       end
#       to_delete.each do |related_uri, group|
#         if related_uri
#           res = GoodData.get("/gdc/md/#{GoodData.project.pid}/userfilters?users=#{related_uri}")
#           items = res['userFilters']['items'].empty? ? [] : res['userFilters']['items'].first['userFilters']
#           GoodData.post("/gdc/md/#{GoodData.project.pid}/userfilters", { 
#             "userFilters" => {
#               "items" => [{
#                 "user" => related_uri,
#                 "userFilters" => items - group.map(&:uri)
#               }]
#             }
#           })
#         end
#         group.each do |filter|
#           filter.delete
#         end
#       end
#       [to_create, to_delete]
#     end
#   end
# end
# 
# def terka_var_example
#   # l9uokhaxn2mjfcab6lwvee2mo20pzc6u
#   # GoodData.logging_on
#   filters = GoodData::UserFilterBuilder::get_filters('vars.csv', {
#     :type => :filter,
#     :labels => [
#       {:label => {:uri => "/gdc/md/lu292gm1077gtv7i383hjl149sva7o1e/obj/2719"} , :column => 'val' },
#     ]
#   });
#   var = GoodData::Variable[3963];
#   GoodData::UserFilterBuilder.execute_variables(filters, var, :dry_run => false)
# end
# 
# 
# def terka_example
#   # l9uokhaxn2mjfcab6lwvee2mo20pzc6u
#   # GoodData.logging_on
#   d = GoodData::Domain['beyond12']
#   filters = GoodData::UserFilterBuilder::get_filters('vars.csv', {
#     :type => :filter,
#     :labels => [
#       {:label => {:uri => "/gdc/md/lu292gm1077gtv7i383hjl149sva7o1e/obj/2719"}, :over => "/gdc/md/lu292gm1077gtv7i383hjl149sva7o1e/obj/2706", :to => "/gdc/md/lu292gm1077gtv7i383hjl149sva7o1e/obj/1785", :column => 'val' },
#       {:label => {:uri => "/gdc/md/lu292gm1077gtv7i383hjl149sva7o1e/obj/2719"}, :over => "/gdc/md/lu292gm1077gtv7i383hjl149sva7o1e/obj/2712", :to => "/gdc/md/lu292gm1077gtv7i383hjl149sva7o1e/obj/368", :column => 'val'}
#     ]
#   });
#   GoodData::UserFilterBuilder.execute_mufs(filters, :domain => d)
# end
# 
# def bcorp_example
#   # xi3hx9tspca0t0t70r0s0cn40inpzl3i
#   # LIVE 8z2c3wx15novcptlafq908aylaxqz468
#   # GoodData.logging_on
#   var = GoodData::Variable.all[0];
#   label = GoodData::DisplayForm["/gdc/md/8z2c3wx15novcptlafq908aylaxqz468/obj/13"];
#   filters = GoodData::UserFilterBuilder::get_filters('portfolioCompanies.csv', {
#     :type => :filter,
#     :labels => [
#       {:label => {:uri => "/gdc/md/8z2c3wx15novcptlafq908aylaxqz468/obj/13"} }
#     ]
#   });
#   GoodData::UserFilterBuilder.execute_variables(filters, var, :dry_run => true, :ignore_missing_values => true)
# end
