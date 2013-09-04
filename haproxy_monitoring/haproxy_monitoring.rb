class HaproxyMonitoring < Scout::Plugin

  if RUBY_VERSION < "1.9"
    needs 'fastercsv'
  else
    # typically, avoid require. In this case we can't use needs' deferred loading because we need to alias CSV
    require 'csv'
    FasterCSV=CSV
  end
  needs 'open-uri'

  OPTIONS=<<-EOS
  uri:
    name: URI
    notes: "URI of the haproxy CSV stats url. See the 'CSV Export' link on your haproxy stats page (example stats page: http://demo.1wt.eu/)."
  proxy:
    notes: The name of the proxy to monitor. Proxies are typically listed in the haproxy.cfg file.
  proxy_type:
    notes: "If multiple proxies have the same name, specify which proxy you want to monitor (ex: 'frontend' or 'backend')."
    attributes: advanced
  user:
    notes: If protected under basic authentication provide the user name.
  password:
    notes: If protected under basic authentication provide the password.
    attributes: password
  EOS

  def build_report

    if option(:uri).nil?
      return error('URI to HAProxy Stats Required', "It looks like the URI to the HAProxy stats page (in csv format) hasn't been provided. Please enter this URI in the plugin settings.")
    end
    proxy = option(:proxy)
    if option(:proxy_type)
      proxy_type = option(:proxy_type)
      if option(:proxy_type) =~ /frontend|backend/i
       proxy_type = proxy_type.upcase
      end
    end
    found_proxies = []
    possible_proxies = []
    begin
      FasterCSV.parse(open(option(:uri),:http_basic_authentication => [option(:user),option(:password)]), :headers => true) do |row|
        next if proxy_type and proxy_type != row["svname"] # ensure the proxy type (if provided) matches
        possible_proxies << row["# pxname"] # used in error message
        next unless proxy.to_s.strip.downcase == row["# pxname"].downcase # ensure the proxy name matches
        # if multiple proxies have the same name, we don't know which to report on. 
        if found_proxies.include?(row["# pxname"])
          data_for_server[:reports] = []
          data_for_server[:memory] = {}
          return error("Multiple proxies have the name '#{proxy}'","Please specify the proxy type (ex: BACKEND or FRONTEND) in the plugin's advanced settings.")
        end
        found_proxies << row["# pxname"]
        
        counter(:requests,    row['stot'].to_i,  :per => :minute)
        counter(:errors_req,  row['ereq'].to_i,  :per => :minute) if row['ereq']
        counter(:errors_conn, row['econ'].to_i,  :per => :minute) if row['econ']
        counter(:errors_resp, row['eresp'].to_i, :per => :minute) if row['eresp']

        counter(:bytes_in,  row['bin'].to_i,  :per => :second) if row['bin']
        counter(:bytes_out, row['bout'].to_i, :per => :second) if row['bout']

        report(:active_sessions => row['scur'])
        report(:queued_sessions => row['qcur']) if row['qcur']

        report(:active_servers => row['act']) if row['act']
        report(:backup_servers => row['bck']) if row['bck']

        hrsp_1xx = row['hrsp_1xx'].to_i if row['hrsp_1xx'] || 0
        hrsp_2xx = row['hrsp_2xx'].to_i if row['hrsp_2xx'] || 0
        hrsp_3xx = row['hrsp_3xx'].to_i if row['hrsp_3xx'] || 0
        hrsp_4xx = row['hrsp_4xx'].to_i if row['hrsp_4xx'] || 0
        hrsp_5xx = row['hrsp_5xx'].to_i if row['hrsp_5xx'] || 0
        hrsp_other = row['hrsp_other'].to_i if row['hrsp_other'] || 0

        counter('hrsp_1xx', hrsp_1xx, :per => :minute)
        counter('hrsp_2xx', hrsp_2xx, :per => :minute)
        counter('hrsp_3xx', hrsp_3xx, :per => :minute)
        counter('hrsp_4xx', hrsp_4xx, :per => :minute)
        counter('hrsp_5xx', hrsp_5xx, :per => :minute)
        counter('hrsp_other', hrsp_other, :per => :minute)

        total = hrsp_1xx + hrsp_2xx + hrsp_3xx + hrsp_4xx + hrsp_5xx + hrsp_other
        hrsp_1xx_percent = hrsp_1xx / total.to_f
        hrsp_2xx_percent = hrsp_2xx / total.to_f
        hrsp_3xx_percent = hrsp_3xx / total.to_f
        hrsp_4xx_percent = hrsp_4xx / total.to_f
        hrsp_5xx_percent = hrsp_5xx / total.to_f
        hrsp_other_percent = hrsp_other / total.to_f

        counter('hrsp_1xx_ratio', hrsp_1xx_percent, :per => :minute)
        counter('hrsp_2xx_ratio', hrsp_2xx_percent, :per => :minute)
        counter('hrsp_3xx_ratio', hrsp_3xx_percent, :per => :minute)
        counter('hrsp_4xx_ratio', hrsp_4xx_percent, :per => :minute)
        counter('hrsp_5xx_ratio', hrsp_5xx_percent, :per => :minute)
        counter('hrsp_other_ratio', hrsp_other_percent, :per => :minute)

        report(:proxy_up=>%w(UP OPEN).find {|s| s == row['status']} ? 1 : 0)
      end # FasterCSV.parse
    rescue OpenURI::HTTPError
      if $!.message == '401 Unauthorized'
        return error("Authentication Failed", "Unable to access the stats page at #{option(:uri)} with the username '#{option(:user)}' and provided password. Please ensure the username, password, and URI are correct.")
      elsif $!.message != '404 Not Found'
        return error("Unable to find the stats page", "The stats page could not be found at: #{option(:uri)}.")
      else
        raise
      end
    rescue FasterCSV::MalformedCSVError
      return error('Unable to access stats page', "The plugin encountered an error attempting to access the stats page (in CSV format) at: #{option(:uri)}. The exception: #{$!.message}\n#{$!.backtrace}")
    end
    if proxy.nil?
      error('Proxy name required',"The name of the proxy to monitor must be provided in the plugin settings. The possible proxies to monitor:\n<ul>#{possible_proxies.map { |p| "<li>#{p}</li>"}.join('')}</ul>")
    elsif found_proxies.empty?
      error('Proxy not found',"The proxy '#{proxy}' #{proxy_type ? "w/proxy type [#{proxy_type}]" : nil} was not found. The possible proxies #{proxy_type ? "for this proxy type" : nil} to monitor:\n<ul>#{possible_proxies.map { |p| "<li>#{p}</li>"}.join('')}</ul>")
    end
  end

end
