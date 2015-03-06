# encoding: UTF-8

require 'csv'
require 'digest'
require 'open-uri'

module GoodData
  module Helpers
    class DataSource
      def initialize(opts = {})
        opts = opts.kind_of?(String) ? { type: :staging, path: opts } : opts
        @source = opts[:type]
        @options = opts
        @realized = false
      end

      def realize_query(params)
        query = @options[:query]
        filename = Digest::SHA256.new.hexdigest(query)
        CSV.open(filename, 'w') do |csv|
          header_written = false
          header = nil
          dwh = params['dwh_client']
          dwh.execute_select(query) do |row|
            unless header_written
              header_written = true
              header = row.keys
              csv << header
            end
            csv << row.values_at(*header)
          end
        end
        filename
      end
      
      def realize_link
        link = @options[:url]
        filename = Digest::SHA256.new.hexdigest(link)
        File.open(filename, 'w') do |f|
          open(link) {|rf| f.write(rf.read) }
        end
        filename
      end

      def realized?
        @realized
      end

      def realize(params = {})
        @realized = true
        case @source.to_s
        when 'ads'
          realize_query(params)
        when 'staging'
          realize_staging
        when 'web'
          realize_link
        end
      end
    end
  end
end
