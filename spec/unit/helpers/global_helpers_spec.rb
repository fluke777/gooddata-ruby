# encoding: UTF-8

require 'gooddata/helpers/csv_helper'

describe GoodData::Helpers do
  describe '#diff' do

    before :each do

      @old_tomas = { id: 1, name: 'Tomas', age: 28 }
      @new_tomas = { id: 1, name: "Lil'Tomas", age: 28 }
      @patrick = { id: 4, name: 'Patrick', age: 24 }
      @old_korczis = { id: 3, name: 'Korczis', age: 23 }
      @new_korczis = { id: 3, name: "Korczis", age: 22 }
      @petr = { id: 2, name: 'Petr', age: 32 }
      @cvengy = { id: 5, name: 'Petr', age: 30 }

      @old_list = [@cvengy, @old_tomas, @patrick, @old_korczis]
      @new_list = [@cvengy, @new_tomas, @petr, @new_korczis]
    end

    it 'diffs two lists of hashes' do
      diff = GoodData::Helpers.diff(@old_list, @new_list, key: :id)

      expect(diff[:same]).to eq [@cvengy]
      expect(diff[:added]).to eq [@petr]
      expect(diff[:removed]).to eq [@patrick]
      expect(diff[:changed]).to eq([
        {
          obj_old: @old_tomas,
          new_obj: @new_tomas, 
          diff: { name: "Lil'Tomas"}
        },
        {
          obj_old: @old_korczis,
          new_obj: @new_korczis,
          diff: { age: 22 }
        }
      ])
    end

    it 'diffs two lists of hashes on subset of fields' do
      diff = GoodData::Helpers.diff(@old_list, @new_list, key: :id, fields: [:id, :age])

      expect(diff[:same]).to eq [@cvengy, @old_tomas]
      expect(diff[:added]).to eq [@petr]
      expect(diff[:removed]).to eq [@patrick]
      expect(diff[:changed]).to eq([
        {
          obj_old: @old_korczis,
          new_obj: @new_korczis,
          diff: { age: 22 }
        }
      ])
    end

    it "shit" do
      x = {
        :companyName=>"GoodData",
        :created=>"2014-05-22 20:33:08",
        :firstName=>"Gem",
        :lastName=>"Tester",
        :login=>"svarovsky+gem_tester@gooddata.com",
        :phoneNumber=>"12345",
        :updated=>"2014-06-24 13:55:28",
        :email=>"svarovsky+gem_tester@gooddata.com",
        :authenticationModes=>[],
        :uri=>"/gdc/account/profile/3cea1102d5584813506352a2a2a00d95"
      }
      y = {
        :email=>"svarovsky+gem_tester@gooddata.com",
        :login=>"svarovsky+gem_tester@gooddata.com",
        :firstname=>"Gem",
        :lastname=>"Tester",
        :role=>"adminRole",
        :password=>"jindrisska",
        :domain=>"gooddata-tomas-svarovsky"
      }
      diff = GoodData::Helpers.diff([x], [y], key: :logn)
      binding.pry
    end

  end
end
