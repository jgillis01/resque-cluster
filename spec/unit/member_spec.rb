require File.expand_path(File.dirname(__FILE__) + '/spec_helper')

RSpec.describe Resque::Cluster::Member do
  before :all do
    @redis = Redis.new

    Resque::Cluster.config = {
      cluster_name: 'unit-test-cluster',
      environment: 'unit-test',
      local_config_path: File.expand_path(File.dirname(__FILE__) + '/../local_config.yml'),
      global_config_path: File.expand_path(File.dirname(__FILE__) + '/../global_config.yml')
    }
    @pool = Resque::Pool.new({})
    @member = Resque::Cluster.init(@pool)
  end

  after :all do
    Resque::Cluster.member.unregister
    Resque::Cluster.config = nil
    Resque::Cluster.member = nil
  end

  context '#cluster_member_settings' do
    before :all do
      @settings_hash = {
        :cluster_maximums => {'foo' => 2, 'bar' => 50, "foo,bar,baz" => 1},
        :host_maximums => {'foo' => 1, 'bar' => 9, "foo,bar,baz" => 1},
        :client_settings => @redis.client.options,
        :rebalance_flag => false,
        :cluster_name => "unit-test-cluster",
        :environment_name => "unit-test"
      }
    end

    it 'returns a correct cluster settings hash' do
      expect(Resque::Cluster.member.send(:cluster_member_settings)).to eq(@settings_hash)
      Resque::Cluster.member.unregister
    end

    it 'returns a correct cluster settings hash with global_config with a rebalance param' do
      Resque::Cluster.config[:global_config_path] = File.expand_path(File.dirname(__FILE__) + '/../global_rebalance_config.yml')
      @settings_hash[:rebalance_flag] = true
      @member = Resque::Cluster.init(@pool)
      expect(Resque::Cluster.member.send(:cluster_member_settings)).to eq(@settings_hash)
    end
  end

  context '#register' do
    before :all do
      @member.register
    end

    it 'pings into redis to let the rest of the cluster know of it' do
      expect(@redis.hget('resque:cluster:unit-test-cluster:unit-test', @@hostname)).to_not be_nil
    end
  end

  context '#check_for_worker_count_adjustment' do
    before :all do
      @redis.hset("GRU:unit-test:unit-test-cluster:global:max_workers","bar",2)
      @redis.hset("GRU:unit-test:unit-test-cluster:#{@@hostname}:max_workers","bar",2)
      @redis.hset("GRU:unit-test:unit-test-cluster:global:workers_running","bar",0)
      @redis.hset("GRU:unit-test:unit-test-cluster:#{@@hostname}:workers_running","bar",0)
    end

    it 'adjust worker counts if an adjustment exists on the local command queue' do
      2.times do
        @member.check_for_worker_count_adjustment
        expect(@redis.hget("GRU:unit-test:unit-test-cluster:#{@@hostname}:workers_running", 'foo')).to eq '1'
        expect(@redis.hget("GRU:unit-test:unit-test-cluster:#{@@hostname}:workers_running", 'bar')).to eq '2'
        expect(@member.pool.config['foo']).to eq(1)
        expect(@member.pool.config['bar']).to eq(2)
      end
    end
  end

  context '#unregister' do
    before :all do
      @member.unregister
    end

    it 'removes everything about itself from redis' do
      expect(@redis.hget('resque:cluster:unit-test-cluster:unit-test', @@hostname)).to be_nil
      expect(@redis.get("resque:cluster:unit-test-cluster:unit-test:#{@@hostname}:running_workers")).to be_nil
    end

    it 'moves all the current running workers into the global queue if rebalance_on_termination is set to true' do
      expect(@redis.hget('GRU:unit-test:unit-test-cluster:global:workers_running', 'bar')).to eq '0'
      expect(@redis.hget('GRU:unit-test:unit-test-cluster:global:workers_running', 'foo')).to eq '0'
      expect(@redis.hget("GRU:unit-test:unit-test-cluster:#{@@hostname}:workers_running", 'bar')).to be_nil
      expect(@redis.hget("GRU:unit-test:unit-test-cluster:#{@@hostname}:workers_running", 'foo')).to be_nil
    end
  end

  after :all do
    @redis.del("GRU:unit-test:unit-test-cluster:global:max_workers")
    @redis.del("GRU:unit-test:unit-test-cluster:global:workers_running")
  end

end
