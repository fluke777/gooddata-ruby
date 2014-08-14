# encoding: UTF-8

require 'gooddata/models/domain'

describe GoodData::Domain do
  before(:each) do
    ConnectionHelper.create_default_connection
  end

  after(:each) do
    GoodData.disconnect
  end

  describe '#add_user' do
    it 'Should add user' do
      user = GoodData::Domain.add_user(:domain => ConnectionHelper::DEFAULT_DOMAIN, :login => "gemtest#{rand(1e6)}@gooddata.com", :password => 'password')
      expect(user).to be_an_instance_of(GoodData::Profile)
      user.delete
    end
  end

  describe '#users' do
    it 'Should list users' do
      users = GoodData::Domain.users(ConnectionHelper::DEFAULT_DOMAIN)
      expect(users).to be_instance_of(Array)
      users.each do |user|
        expect(user).to be_an_instance_of(GoodData::Profile)
      end
    end

    it 'Accepts pagination options - limit' do
      users = GoodData::Domain.users(ConnectionHelper::DEFAULT_DOMAIN, {:limit =>1})
      expect(users).to be_instance_of(Array)
      users.each do |user|
        expect(user).to be_an_instance_of(GoodData::Profile)
      end
    end

    it 'Accepts pagination options - offset' do
      users = GoodData::Domain.users(ConnectionHelper::DEFAULT_DOMAIN, {:offset => 1})
      expect(users).to be_instance_of(Array)
      users.each do |user|
        expect(user).to be_an_instance_of(GoodData::Profile)
      end
    end
  end

  describe '#users_create' do
    it 'Creates new users from list' do
      list = []
      (0...10).each do |i|
        num = rand(1e6)
        login = "gemtest#{num}@gooddata.com"

        json = {
          'user' => {
            'content' => {
              'email' => login,
              'login' => login,
              'firstname' => 'the',
              'lastname' => num.to_s,

              # Following lines are ugly hack
              'role' => 'admin',
              'password' => 'password',
              'domain' => ConnectionHelper::DEFAULT_DOMAIN,

              # And following lines are even much more ugly hack
              # 'sso_provider' => '',
              # 'authentication_modes' => ['sso', 'password']
            },
            'meta' => {}
          }
        }
        user = GoodData::Membership.new(json)
        list << user
      end

      res = GoodData::Domain.users_create(list, ConnectionHelper::DEFAULT_DOMAIN)

      expect(res).to be_an_instance_of(Array)

      # no errors
      expect(res.select { |x| x[:type] == :user_added_to_domain }.count).to eq res.count

      res.map { |r| r[:user] }.each do |r|
        expect(r).to be_an_instance_of(GoodData::Profile)
        r.delete
      end
    end
  end

  describe '#users_create' do
    it 'Update a users from list' do

      domain = GoodData::Domain[ConnectionHelper::DEFAULT_DOMAIN]
      user = domain.users.sample
      login = user.login
      user.first_name = user.first_name.reverse
      GoodData::Domain.users_create([user.to_hash], ConnectionHelper::DEFAULT_DOMAIN)
      changed_user = domain.users.find { |user| user.login == login }
      expect(changed_user.first_name).to eq user.first_name
    end
  end
end
