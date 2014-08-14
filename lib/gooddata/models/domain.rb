# encoding: UTF-8

require_relative 'profile'
require_relative '../extensions/enumerable'

module GoodData
  class Domain
    attr_reader :name

    USERS_OPTIONS = { :offset => 0, :limit => 1000 }

    class << self
      # Looks for domain
      #
      # @param domain_name [String] Domain name
      # @return [String] Domain object instance
      def [](domain_name, options = {})
        fail "Using pseudo-id 'all' is not supported by GoodData::Domain" if domain_name.to_s == 'all'
        GoodData::Domain.new(domain_name)
      end

      # Adds user to domain
      #
      # @param domain [String] Domain name
      # @param login [String] Login of user to be invited
      # @param password [String] Default preset password
      # @return [Object] Raw response
      def add_user(opts)
        generated_pass = rand(10E10).to_s
        data = {
          :login => opts[:login],
          :firstName => opts[:first_name] || 'FirstName',
          :lastName => opts[:last_name] || 'LastName',
          :password => opts[:password] || generated_pass,
          :verifyPassword => opts[:password] || generated_pass,
          :email => opts[:login]
        }

        # Optional authentication modes
        tmp = opts[:authentication_modes]
        if tmp
          if tmp.kind_of? Array
            data[:authenticationModes] = tmp
          elsif tmp.kind_of? String
            data[:authenticationModes] = [tmp]
          end
        end

        # Optional company
        tmp = opts[:company_name]
        tmp = opts[:company] if tmp.nil? || tmp.empty?
        data[:companyName] = tmp if tmp && !tmp.empty?

        # Optional country
        tmp = opts[:country]
        data[:country] = tmp if tmp && !tmp.empty?

        # Optional phone number
        tmp = opts[:phone]
        tmp = opts[:phone_number] if tmp.nil? || tmp.empty?
        data[:phoneNumber] = tmp if tmp && !tmp.empty?

        # Optional position
        tmp = opts[:position]
        data[:position] = tmp if tmp && !tmp.empty?

        # Optional sso provider
        tmp = opts[:sso_provider]
        data['ssoProvider'] = tmp if tmp && !tmp.empty?

        # Optional timezone
        tmp = opts[:timezone]
        data[:timezone] = tmp if tmp && !tmp.empty?

        # TODO: It will be nice if the API will return us user just newly created
        
        url = "/gdc/account/domains/#{opts[:domain]}/users"
        response = GoodData.post(url, :accountSetting => data)

        raw = GoodData.get response['uri']

        # TODO: Remove this hack when POST /gdc/account/domains/{domain-name}/users returns full profile
        raw['accountSetting']['links'] = {} unless raw['accountSetting']['links']
        raw['accountSetting']['links']['self'] = response['uri'] unless raw['accountSetting']['links']['self']

        GoodData::Profile.new(raw)
      end

      def update_user(opts)
        # generated_pass = rand(10E10).to_s
        data = {
          :firstName => opts[:firstName] || 'FirstName',
          :lastName => opts[:lastName] || 'LastName',
          :email => opts[:email]
        }

        # Optional authentication modes
         tmp = opts[:authentication_modes]
         if tmp
           if tmp.kind_of? Array
             data[:authenticationModes] = tmp
           elsif tmp.kind_of? String
             data[:authenticationModes] = [tmp]
           end
         end
        
         # Optional company
         tmp = opts[:company_name]
         tmp = opts[:company] if tmp.nil? || tmp.empty?
         data[:companyName] = tmp if tmp && !tmp.empty?
        
         # Optional pass
         tmp = opts[:password]
         tmp = opts[:password] if tmp.nil? || tmp.empty?
         data[:password] = tmp if tmp && !tmp.empty?
         data[:verifyPassword] = tmp if tmp && !tmp.empty?
        
         # Optional country
         tmp = opts[:country]
         data[:country] = tmp if tmp && !tmp.empty?
        
         # Optional phone number
         tmp = opts[:phone]
         tmp = opts[:phone_number] if tmp.nil? || tmp.empty?
         data[:phoneNumber] = tmp if tmp && !tmp.empty?
        
         # Optional position
         tmp = opts[:position]
         data[:position] = tmp if tmp && !tmp.empty?
        
         # Optional sso provider
         tmp = opts[:sso_provider]
         data['ssoProvider'] = tmp if tmp && !tmp.empty?
        
         # Optional timezone
         tmp = opts[:timezone]
         data[:timezone] = tmp if tmp && !tmp.empty?
 
        # TODO: It will be nice if the API will return us user just newly created
        url = opts.delete(:uri)
        if GoodData.profile.uri == url
          data.delete(:password)
        end
        response = GoodData.put(url, :accountSetting => data)
        
        # TODO: Remove this hack when POST /gdc/account/domains/{domain-name}/users returns full profile
        response['accountSetting']['links'] = {} unless response['accountSetting']['links']
        response['accountSetting']['links']['self'] = url unless response['accountSetting']['links']['self']
        GoodData::Profile.new(response)
      end


      # Finds user in domain by login
      #
      # @param domain [String] Domain name
      # @param login [String] User login
      # @return [GoodData::Profile] User profile
      def find_user_by_login(domain, login)
        url = "/gdc/account/domains/#{domain}/users?login=#{login}"
        tmp = GoodData.get url
        items = tmp['accountSettings']['items'] if tmp['accountSettings']
        return GoodData::Profile.new(items.first) if items && items.length > 0
        nil
      end

      # Returns list of users for domain specified
      # @param [String] domain Domain to list the users for
      # @param [Hash] opts Options.
      # @option opts [Number] :offset The subject
      # @option opts [Number] :limit From address
      # TODO: Review opts[:limit] functionality
      def users(domain, opts = USERS_OPTIONS)
        result = []

        options = USERS_OPTIONS.merge(opts)
        offset = 0 || options[:offset]
        uri = "/gdc/account/domains/#{domain}/users?offset=#{offset}&limit=#{options[:limit]}"
        loop do
          break unless uri
          tmp = GoodData.get(uri)
          tmp['accountSettings']['items'].each do |account|
            result << GoodData::Profile.new(account)
          end
          uri = tmp['accountSettings']['paging']['next']
        end

        result
      end

      # Create users specified in list
      # @param [Array<GoodData::Membership>] list List of users
      # @param [String] default_domain_name Default domain name used when no specified in user
      # @return [Array<GoodData::User>] List of users created
      def users_create(list, default_domain = nil, options = {})
        ignore_failures = options[:ignore_failures]
        default_domain_name = default_domain.respond_to?(:name) ? default_domain.name : default_domain
        domains = {}
        list.map do |user|
          begin
            user_data = user.to_hash
            # TODO: Add user here
            domain_name = user_data[:domain] || default_domain_name

            # Lookup for domain in cache'
            domain = domains[domain_name]

            # Get domain info from REST, add to cache
            if domain.nil?
              domain = {
                :domain => GoodData::Domain[domain_name],
                :users => GoodData::Domain[domain_name].users
              }

              domain[:users_map] = Hash[domain[:users].map { |u| [u.login, u] }]
              domains[domain_name] = domain
            end

            # Check if user exists in domain
            domain_user = domain[:users_map][user_data[:login]]

            # Create domain user if needed
            unless domain_user
              # Add created user to cache
              domain_user = domain[:domain].add_user(user_data)
              domain[:users] << domain_user
              domain[:users_map][domain_user.login] = domain_user
              { type: :user_added_to_domain, user: domain_user }
            else
              # fields = [:firstName, :email]
              diff = GoodData::Helpers.diff([domain_user.to_hash], [user_data], key: :login)
              next if[:changed].empty?
              domain_user = domain[:domain].update_user(domain_user.to_hash.merge(user_data.compact))
              domain[:users_map][domain_user.login] = domain_user            
              { type: :user_changed_in_domain, user: domain_user }
            end
          rescue RuntimeError => e
            { type: :errors, reason: e}
          end
        end
      end
    end

    def initialize(domain_name)
      @name = domain_name
    end

    # Adds user to domain
    #
    # @param login [String] Login of user to be invited
    # @param password [String] Default preset password
    # @return [Object] Raw response
    #
    # Example
    #
    # GoodData.connect 'tomas.korcak@gooddata.com' 'your-password'
    # domain = GoodData::Domain['gooddata-tomas-korcak']
    # domain.add_user 'joe.doe@example', 'sup3rS3cr3tP4ssW0rtH'
    #
    def add_user(opts)
      opts[:domain] = name
      GoodData::Domain.add_user(opts)
    end

    # Update user in domain
    #
    # @param opts [Hash] Data of the user to be updated
    # @return [Object] Raw response
    #
    #
    def update_user(opts)
      GoodData::Domain.update_user(opts)
    end

    # Finds user in domain by login
    #
    # @param login [String] User login
    # @return [GoodData::Profile] User account settings
    def find_user_by_login(login)
      GoodData::Domain.find_user_by_login(name, login)
    end

    # List users in domain
    #
    # @param [Hash] opts Additional user listing options.
    # @option opts [Number] :offset Offset to start listing from
    # @option opts [Number] :limit Limit of users to be listed
    # @return [Array<GoodData::Profile>] List of user account settings
    #
    # Example
    #
    # GoodData.connect 'tomas.korcak@gooddata.com' 'your-password'
    # domain = GoodData::Domain['gooddata-tomas-korcak']
    # pp domain.users
    #
    def users(opts = USERS_OPTIONS)
      GoodData::Domain.users(name, opts)
    end

    def users_create(list, options = {})
      GoodData::Domain.users_create(list, name, options)
    end

    private

    # Private setter of domain name. Used by constructor not available for external users.
    #
    # @param domain_name [String] Domain name to be set.
    def name=(domain_name) # rubocop:disable TrivialAccessors
      @name = domain_name
    end
  end
end
