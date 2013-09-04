require File.expand_path('../../test_helper.rb', __FILE__)
require File.expand_path('../haproxy_monitoring.rb', __FILE__)

require 'open-uri'
class HaProxyTest < Test::Unit::TestCase

  def teardown
    FakeWeb.clean_registry
  end
  
  def test_should_error_with_non_unique_proxy_names
    uri='http://fake'
    proxy = 'metrics-api'
    FakeWeb.register_uri(:get, uri, :body => File.read(File.dirname(__FILE__)+'/fixtures/non_unique_proxies.csv'))
    @plugin=HaproxyMonitoring.new(nil,{},{:uri=>uri, :proxy => proxy})
    res = @plugin.run()
    assert res[:reports].empty?
    assert res[:memory].empty?
    assert res[:errors].any?  
    assert res[:errors].first[:subject] =~ /Multiple proxies/
    
  end
  
  def test_should_run_with_proxy_type
    uri='http://fake'
    proxy = 'metrics-api'
    time = Time.now
    Timecop.travel(time-60*10) do
      FakeWeb.register_uri(:get, uri, :body => File.read(File.dirname(__FILE__)+'/fixtures/non_unique_proxies.csv'))
      @plugin=HaproxyMonitoring.new(nil,{},{:uri=>uri, :proxy => proxy, :proxy_type => 'backend'})
      res = @plugin.run()
      assert_equal 61, res[:memory]["_counter_requests"][:value]
      assert_equal 1, res[:reports].find { |e| e[:proxy_up]}[:proxy_up]
      first_run_memory = res[:memory]
      
      # now - 10 minutes later
      Timecop.travel(time) do
        FakeWeb.register_uri(:get, uri, :body => File.read(File.dirname(__FILE__)+'/fixtures/non_unique_proxies.csv'))
        @plugin=HaproxyMonitoring.new(time-60*10,first_run_memory,{:uri=>uri, :proxy => proxy, :proxy_type => 'backend'})
        res = @plugin.run()
        assert_in_delta 0, res[:reports].first[:requests], 0
        assert_equal 1, res[:reports].find { |e| e[:proxy_up]}[:proxy_up]
      end # 2nd run
    end # travel
  end

  def test_should_run
    # Stub the plugin instance where necessary and run
    # @plugin=PluginName.new(last_run, memory, options)
    #                        date      hash    hash
    uri='http://fake'
    proxy = 'rails'
    time = Time.now
    Timecop.travel(time-60*10) do
      FakeWeb.register_uri(:get, uri, :body => File.read(File.dirname(__FILE__)+'/fixtures/sample.csv'))
      @plugin=HaproxyMonitoring.new(nil,{},{:uri=>uri, :proxy => proxy})
      res = @plugin.run()
      assert_equal 120350789, res[:memory]["_counter_requests"][:value]
      assert_equal 10860, res[:memory]["_counter_errors_req"][:value]
      assert_equal 10, res[:memory]["_counter_errors_conn"][:value]
      assert_equal 20, res[:memory]["_counter_errors_resp"][:value]
      assert_equal 1, res[:reports].find { |hash| hash[:proxy_up] }.values.last
      first_run_memory = res[:memory]
      
      # now - 10 minutes later
      Timecop.travel(time) do
        FakeWeb.register_uri(:get, uri, :body => File.read(File.dirname(__FILE__)+'/fixtures/sample_second_run.csv'))
        @plugin=HaproxyMonitoring.new(time-60*10,first_run_memory,{:uri=>uri, :proxy => 'rails'})
        res = @plugin.run()
        assert_in_delta 10, res[:reports].first[:requests], 0.001
        assert_in_delta 1, res[:reports].find { |e| e[:errors_req]}[:errors_req], 0.001
        assert_in_delta 0, res[:reports].find { |e| e[:errors_conn]}[:errors_conn], 0.001
        assert_in_delta 0.1, res[:reports].find { |e| e[:errors_resp]}[:errors_resp], 0.001      
        assert_equal 0, res[:reports].find { |hash| hash[:proxy_up] }.values.last
      end # 2nd run
    end # travel
  end
  
  def test_should_error_with_no_proxy_provided
    uri='http://fake' # output comes from http://demo.1wt.eu/;csv
    FakeWeb.register_uri(:get, uri, :body => File.read(File.dirname(__FILE__)+'/fixtures/sample.csv'))
    @plugin=HaproxyMonitoring.new(nil,{},{:uri=>uri})
    res = @plugin.run()
    error = res[:errors].first
    assert_equal "Proxy name required", error[:subject]
  end
  
  def test_should_error_with_proxy_not_found
    uri='http://fake' # output comes from http://demo.1wt.eu/;csv
    FakeWeb.register_uri(:get, uri, :body => File.read(File.dirname(__FILE__)+'/fixtures/sample.csv'))
    @plugin=HaproxyMonitoring.new(nil,{},{:uri=>uri, :proxy => 'invalid'})
    res = @plugin.run()
    error = res[:errors].first
    assert_equal "Proxy not found", error[:subject]
  end

  def test_should_error_with_invalid_csv
    uri='http://fake'
    FakeWeb.register_uri(:get, uri, :body => File.read(File.dirname(__FILE__)+'/fixtures/invalid.csv'))
    @plugin=HaproxyMonitoring.new(nil,{},{:uri=>uri,:proxy => 'rails'})

    res = @plugin.run()
    assert_equal 0, res[:reports].size
    assert_equal 1, res[:errors].size
    assert_equal "Unable to access stats page", res[:errors].first[:subject]
  end
  
  def test_should_error_with_blank_uri
    @plugin=HaproxyMonitoring.new(nil,{},{:uri=>nil})

    res = @plugin.run()
    assert_equal 0, res[:reports].size
    assert_equal 1, res[:errors].size
    assert_equal "URI to HAProxy Stats Required", res[:errors].first[:subject]
  end
  
  def test_should_error_with_invalid_basic_auth
    uri_no_auth = "http://example.com/secret"
    uri_invalid_auth = "http://user:invalid@example.com/secret"
    FakeWeb.register_uri(:get, uri_no_auth, :body => "Unauthorized", :status => ["401", "Unauthorized"])
    FakeWeb.register_uri(:get, uri_invalid_auth, :body => "Unauthorized", :status => ["401", "Unauthorized"])

    @plugin=HaproxyMonitoring.new(nil,{},{:uri=>uri_no_auth, :user => 'user', :password => 'invalid'})
    res = @plugin.run()
    assert_equal 1, res[:errors].size
    assert_equal "Authentication Failed", res[:errors].first[:subject]
  end
  
  def test_should_run_with_valid_basic_auth
    uri_no_auth = "http://example.com/secret"
    uri = "http://user:pass@example.com/secret"
    FakeWeb.register_uri(:get, uri_no_auth, :body => "Unauthorized", :status => ["401", "Unauthorized"])
    FakeWeb.register_uri(:get, uri, :body => File.read(File.dirname(__FILE__)+'/fixtures/sample.csv'))
    
    @plugin=HaproxyMonitoring.new(nil,{},{:uri=>uri_no_auth, :user => 'user', :password => 'pass', :proxy => 'rails'})
    res = @plugin.run()
    assert res[:errors].empty?
    assert res[:memory].any?
  end

  def test_should_count_http_status_code
    uri_no_auth = "http://example.com/secret"
    uri = "http://user:pass@example.com/secret"
    FakeWeb.register_uri(:get, uri_no_auth, :body => "Unauthorized", :status => ["401", "Unauthorized"])
    FakeWeb.register_uri(:get, uri, :body => File.read(File.dirname(__FILE__)+'/fixtures/status_codes.csv'))
    
    @plugin=HaproxyMonitoring.new(nil,{},{:uri=>uri_no_auth, :user => 'user', :password => 'pass', :proxy => 'rails'})
    res = @plugin.run()
    assert res[:errors].empty?
    assert res[:memory].any?
  end
end
