require 'resque/cluster/member'

module Resque
  # Distributed Pool is a clustered resque-pool
  class Cluster
    class << self
      attr_accessor :config, :member

      def init(started_pool)
        @member = Member.new(started_pool)
      end
    end
  end
end
