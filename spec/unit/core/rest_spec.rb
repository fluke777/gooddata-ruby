# encoding: UTF-8

require 'gooddata/core/rest'

describe GoodData do
  before(:each) do
    @client = ConnectionHelper.create_default_connection
    @project = ProjectHelper.get_default_project(:client => @client)
  end

  after(:each) do
    @client.disconnect
  end

  describe '#get_project_webdav_path' do
    it 'Returns path' do
      file_name = 'test-file.csv'
      result = @client.get_project_webdav_path(file_name, project: @project)
      expect(result.to_s).to eq ("https://secure-di.gooddata.com/project-uploads/#{@project.pid}/#{file_name}")
    end
  end

  describe '#upload_to_project_webdav' do
    it 'Uploads file to project storage' do
      file_name = 'spec/data/test-ci-data.csv'
      result = @client.upload_to_project_webdav(file_name, project: @project)
      expect(result.to_s).to eq ("https://secure-di.gooddata.com/project-uploads/#{@project.pid}/#{file_name}")
      s = StringIO.new
      @client.download(result, s)
      expect(s.string).to eq File.read(file_name)
    end
  end

  describe '#upload_to_user_webdav' do
    it 'Uploads file to user storage' do
      file_name = 'spec/data/test-ci-data.csv'
      result = @client.upload_to_user_webdav(file_name)
      expect(result.to_s).to eq ("https://secure-di.gooddata.com/uploads/test-ci-data.csv")
      s = StringIO.new
      @client.download(result, s)
      expect(s.string).to eq File.read(file_name)
    end
  end

  describe '#get_user_webdav_path' do
    it 'Gets the path' do
      result = @client.get_user_webdav_path('test.csv')
      expect(result.to_s).to eq "https://secure-di.gooddata.com/uploads/test.csv"
    end
  end
end
