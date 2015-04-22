# encoding: UTF-8
require 'restclient/exceptions'

module GoodData
  # Project Not Found
  class ProjectNotFound < RuntimeError
    attr_accessor :project_id

    def initialize(project_id = 'N/A')
      super("Project #{project_id} was not found.")
      @project_id = project_id
    end
  end
end
