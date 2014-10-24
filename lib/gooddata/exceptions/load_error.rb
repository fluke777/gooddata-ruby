# encoding: UTF-8

module GoodData
  class DataMartLoadError < RuntimeError
    DEFAULT_MSG = 'Load to data mart failed'

    def initialize(msg = DEFAULT_MSG)
      super(msg)
    end
  end
end
