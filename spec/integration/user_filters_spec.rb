require 'gooddata'

describe "User filters implementation", :constraint => 'slow' do
  before(:all) do
    @spec = JSON.parse(File.read("./spec/data/test_project_model_spec.json"), :symbolize_names => true)
    ConnectionHelper::create_default_connection
    @project = GoodData::Model::ProjectCreator.migrate({:spec => @spec, :token => ConnectionHelper::GD_PROJECT_TOKEN})
    GoodData.logging_on
    GoodData.with_project(@project) do |p|
      @label = GoodData::Attribute.find_first_by_title('Dev').label_by_name('email')
      
      blueprint = GoodData::Model::ProjectBlueprint.new(@spec)
      commits_data = [
        ["lines_changed","committed_on","dev_id","repo_id"],
        [1,"01/01/2014",1,1],
        [3,"01/02/2014",2,2],
        [5,"05/02/2014",3,1]]
      blueprint.find_dataset('commits').upload(commits_data)

      devs_data = [
        ["dev_id", "email"],
        [1, "tomas@gooddata.com"],
        [2, "petr@gooddata.com"],
        [3, "jirka@gooddata.com"]]
      blueprint.find_dataset('devs').upload(devs_data)
    end
  end

  after(:all) do
    @project.delete if @project
  end

  it "should create a mandatory user filter" do
    GoodData.with_project(@project) do |p|
      filters = [[ConnectionHelper::DEFAULT_USERNAME, @label.uri, 'tomas@gooddata.com', 'jirka@gooddata.com']]

      metric = GoodData::Metric.xcreate(:expression => "SELECT SUM(#\"Lines changed\")", :title => 'x')

      # [jirka@gooddata.com | petr@gooddata.com | tomas@gooddata.com]
      # [5.0                | 3.0               | 1.0               ]

      metric.execute.should == 9
      GoodData::UserFilterBuilder.execute_mufs(filters)
      metric.execute.should == 1
      r = GoodData::ReportDefinition.execute :left => [metric], :top => [@label.attribute]
      r.include_column?(['tomas@gooddata.com', 1]).should == true

      filters = [[ConnectionHelper::DEFAULT_USERNAME, @label.uri, "petr@gooddata.com"]]
      GoodData::UserFilterBuilder.execute_mufs(filters)

      r.include_column?(['tomas@gooddata.com', 1]).should == false
      r.include_column?(['petr@gooddata.com', 3]).should == true

      GoodData::MandatoryUserFilter.all.each { |f| f.delete }
    end
  end

  it "should fail when asked to set a user not in project" do
    GoodData.with_project(@project) do |p|
      
      filters = [['nonexistent_user@gooddata.com', @label.uri, "tomas@gooddata.com"]]
      expect do
        GoodData::UserFilterBuilder.execute_mufs(filters)
      end.to raise_error
    end
  end

  it "should fail when asked to set a value not in the proejct" do
    GoodData.with_project(@project) do |p|
      filters = [['nonexistent_user@gooddata.com', @label.uri, "%^&*( nonexistent value"]]
      expect do
        GoodData::UserFilterBuilder.execute_mufs(filters)
      end.to raise_error
    end
  end

  it "should be able to add mandatory filter to a user not in the project if domain is provided" do
    pending('resolve domain')
    d = GoodData::Domain['domain_name']
    GoodData.with_project(@project) do |p|
      filters = [['nonexistent_user@gooddata.com', @label.uri, "tomas@gooddata.com"]]
      expect do
        GoodData::UserFilterBuilder.execute_mufs(filters, :domain => d)
      end.to raise_error
    end
  end

end
