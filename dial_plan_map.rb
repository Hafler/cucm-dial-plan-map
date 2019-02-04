#!/usr/bin/env ruby
require 'getoptlong'
require 'savon'
require 'ruby-graphviz'
require 'ipaddress'

# Main
END {
  process_opts
  generate_client
  route_gateway_response = perform_query(route_gateway_sql)
  route_trunk_response = perform_query(route_trunk_sql)
  generate_map(route_gateway_response, route_trunk_response)
}

# Gather and process CLI options
def process_opts
  set_default_opts
  opts = get_opts
  opts.each do |opt, arg|
    arg = arg.to_s
    case opt
    when '--help'
      print_help
    when '--ip_address'
      verify_ip_address(arg)
      @ip_address = arg
    when '--username'
      @username = arg
    when '--password'
      @password = arg
    when '--port'
      @port = arg
    when '--version'
      @version = arg.to_i.to_s
    when '--css'
      @filter_opts[:css] = arg
    when '--partition'
      @filter_opts[:partition] = arg
    when '--pattern'
      @filter_opts[:pattern] = arg
    when '--route_list'
      @filter_opts[:route_list] = arg
    when '--route_group'
      @filter_opts[:route_group] = arg
    when '--device'
      @filter_opts[:device] = arg
    end
  end
  print_help if @ip_address.nil? || @username.nil? || @password.nil?
end

# Set up some default global variables
def set_default_opts
  @ip_address = nil
  @username = nil
  @password = nil
  @port = '8443'
  @version = '10'
  @filter_opts = {}
end

# Get options from command line
# See print_help for more information regarding each opt
def get_opts
  GetoptLong.new(
    ['--help', GetoptLong::NO_ARGUMENT],
    ['--ip_address', GetoptLong::REQUIRED_ARGUMENT],
    ['--port', GetoptLong::OPTIONAL_ARGUMENT],
    ['--username', GetoptLong::REQUIRED_ARGUMENT],
    ['--password', GetoptLong::REQUIRED_ARGUMENT],
    ['--version', GetoptLong::OPTIONAL_ARGUMENT],
    ['--css', GetoptLong::OPTIONAL_ARGUMENT],
    ['--partition', GetoptLong::OPTIONAL_ARGUMENT],
    ['--pattern', GetoptLong::OPTIONAL_ARGUMENT],
    ['--route_list', GetoptLong::OPTIONAL_ARGUMENT],
    ['--route_group', GetoptLong::OPTIONAL_ARGUMENT],
    ['--device', GetoptLong::OPTIONAL_ARGUMENT]
  )
end

# Verify that the CUCM IP address is in-fact a valid IP address
def verify_ip_address(ip)
  unless IPAddress.valid? ip
    puts 'IP Address is not valid. Exiting!'
    print_help
  end
end

# Prints the help dialog to screen
def print_help
  puts <<-EOF

Command:
  ruby dial_plan_map.rb [OPTIONS]

Options:
  --help
    Show the help dialog

  --ip_address
    Required: Defines the ip address of the Call Manager

  --port
    Optional: Defines the port to use to connect to the Call Manager API. Default: 8443

  --username
    Required: Defines the username to use to connect to the Call Manager API

  --password
    Required: Defines the password to use to connect to the Call Manager API

  --version
    Optional: Defines the CUCM version to use to connec to the Call Manager API. Default: 10.0

  --css
    Optional: Defines a filter for calling search spaces. Use % for wildcard

  --partition
    Optional: Defines a filter for partitions. Use % for wildcard

  --pattern
    Optional: Defines a filter for patterns. Patterns are represented in the format of 'dn/partition'. Use % for wildcard

  --route_list
    Optional: Defines a filter for route list names. Use % for wildcard

  --route_group
    Optional: Defines a filter for route group names. Use % for wildcard

  --device
    Optional: Defines a filter for device names. Use % for wildcard

  EOF
  exit 0
end

# Generate SOAP client for AXL communication
# @return [Savon::Client]
def generate_client
  @client = generate_soap_client_axl("https://#{@ip_address}:#{@port}/axl")
end

# Generate a soap client that has an Action header
# @param action [String] The action to be injected into the soap header
# @param url [String] The url to be used for SOAP client interaction
# @return [Savon::Client] The soap client object
def generate_soap_client_axl(url)
  Savon.client(
    endpoint: url,
    namespace: 'http://www.cisco.com/AXL/API/' + @version + '.0',
    namespace_identifier: 'ns1',
    basic_auth: [@username, @password],
    ssl_verify_mode: :none,
    follow_redirects: true,
    convert_request_keys_to: :none
  )
end

# Query CUCM via AXL api to gather dial plan details
# @param query [String] The AXL executeSQLQuery string to be presented to the AXL API
# @return [Array] An array of hashes, each hash is one record returned from the executeSQLQuery response
def perform_query(query)
  query_response = @client.call(:executeSQLQuery, message: { 'sql' => query })
  query_response.body.dig(:execute_sql_query_response, :return, :row)
rescue Savon::HTTPError => e
  puts 'Could not access AXL API. Check credentials. Exiting!'
  exit 1
end

# Defines the SQL to send when querying for route pattern -> route_list -> route_group relationships
# @return [String] The SQL string to send to the AXL API
def route_gateway_sql
  base_sql = 'SELECT css.name AS css,
  rp.name AS partition,
  CONCAT(CONCAT(n.dnorpattern,"/"),rp.name) AS pattern,
  d.name AS route_list,
  rg.name AS route_group,
  dd.name AS destination
  FROM callingsearchspace AS css
    INNER JOIN callingsearchspacemember csm ON csm.fkcallingsearchspace = css.pkid
    INNER JOIN routepartition rp ON csm.fkroutepartition = rp.pkid
    INNER JOIN numplan n ON rp.pkid = n.fkroutepartition
    INNER JOIN devicenumplanmap AS dmap ON dmap.fknumplan=n.pkid
    INNER JOIN device AS d ON dmap.fkdevice=d.pkid
    LEFT JOIN routelist AS rl ON rl.fkdevice = d.pkid
    INNER JOIN routegroup AS rg ON rg.pkid=rl.fkroutegroup
    INNER JOIN RouteGroupDeviceMap rgdp ON rgdp.fkRouteGroup=rg.pkid
    INNER JOIN device dd ON dd.pkid=rgdp.fkDevice
  WHERE n.tkpatternusage=5 '
  sql = add_filters('gateway', base_sql)
  sql += 'ORDER BY css.name, csm.sortorder'
  sql
end

# Defines the SQL to send when querying for route pattern -> trunk relationships
# @return [String] The SQL string to send to the AXL API
def route_trunk_sql
  base_sql = 'SELECT css.name AS css,
  rp.name AS partition,
  CONCAT(CONCAT(n.dnorpattern,"/"),rp.name) AS pattern,
  d.name AS destination
  FROM callingsearchspace AS css
    INNER JOIN callingsearchspacemember csm ON csm.fkcallingsearchspace = css.pkid
    INNER JOIN routepartition rp ON csm.fkroutepartition = rp.pkid
    INNER JOIN numplan n ON rp.pkid = n.fkroutepartition
    INNER JOIN devicenumplanmap AS dmap ON dmap.fknumplan=n.pkid
    INNER JOIN device AS d ON dmap.fkdevice=d.pkid
    LEFT JOIN routelist AS rl ON rl.fkdevice = d.pkid
    LEFT JOIN routegroup AS rg ON rg.pkid=rl.fkroutegroup
    LEFT JOIN RouteGroupDeviceMap rgdp ON rgdp.fkRouteGroup=rg.pkid
    LEFT JOIN device dd ON dd.pkid=rgdp.fkDevice
  WHERE n.tkpatternusage=5
  AND rg.name IS NULL '
  sql = add_filters('trunk', base_sql)
  sql = base_sql + 'ORDER BY css.name, csm.sortorder'
  sql
end

# Defines AND filters to add on to the base SQL based on options passed in via command line arguments
# @param type [String] Defines the type of SQL string to be passed in
# @param sql [String] The SQL string to add filters to
# @return [String] The SQL string with filters to be send to the AXL API
def add_filters(type, sql)
  @filter_opts.each do |opt, arg|
    case opt
    when :css
      sql += "AND lower(css.name) LIKE lower('#{arg}') "
    when :partition
      sql += "AND lower(rp.name) LIKE lower('#{arg}') "
    when :pattern
      sql += "AND lower(pattern) LIKE lower('#{arg}') "
    when :route_list
      sql += "AND lower(d.name) LIKE lower('#{arg}') " unless type.eq('trunk')
    when :route_group
      sql += "AND lower(rg.name) LIKE lower('#{arg}') " unless type.eq('trunk')
    when :device
      sql += "AND lower(dd.name) LIKE lower('#{arg}') "
    end
  end
  sql
end

# Generates a PDF with the dial plan mapped out
# @param route_gateway [Array] An array of hashes, each hash is one record returned from the executeSQLQuery response
# @param route_trunk [Array] An array of hashes, each hash is one record returned from the executeSQLQuery response
def generate_map(route_gateway, route_trunk)
  # Check to see if we had no records, exit if we do
  if route_gateway.nil? && route_trunk.nil?
    puts 'No records were found. Exiting!'
    exit 0
  end

  # Generate parent graph
  GraphViz.new(:G, type: :digraph, ranksep: '10.0', concentrate: 'true', compound: 'true') do |g|
    # Generate sub graphs
    graph_css = g.add_graph('graph_css', rank: 'same')
    graph_partition = g.add_graph('graph_partition', rank: 'same')
    graph_pattern = g.add_graph('graph_pattern', rank: 'same')
    graph_route_list = g.add_graph('route_list', rank: 'same')
    graph_route_group = g.add_graph('route_group', rank: 'same')
    graph_destination = g.add_graph('device', rank: 'max')

    # Generate graph associations for route_lists
    unless route_gateway.nil?
      generate_associations(g, route_gateway, graph_css, :css, graph_partition, :partition)
      generate_associations(g, route_gateway, graph_partition, :partition, graph_pattern, :pattern)
      generate_associations(g, route_gateway, graph_pattern, :pattern, graph_route_list, :route_list)
      generate_associations(g, route_gateway, graph_route_list, :route_list, graph_route_group, :route_group)
      generate_associations(g, route_gateway, graph_route_group, :route_group, graph_destination, :destination)
    end

    # Generate graph associations for SIP Trunks
    unless route_trunk.nil?
      generate_associations(g, route_trunk, graph_css, :css, graph_partition, :partition)
      generate_associations(g, route_trunk, graph_partition, :partition, graph_pattern, :pattern)
      generate_associations(g, route_trunk, graph_pattern, :pattern, graph_destination, :destination)
    end
  end.output(pdf: 'dial_plan_map.pdf')
end

# Ganerates nodes and edges(arrows) on the graph to map out the dial plan
# Nodes and edges are made to be unique, so there will never be more than one edge between nodes and never more than one of the same node
# @param parent [Graphviz] The parent graph
# @param data [Array] An array of hashes, each hash is one record returned from the executeSQLQuery response
# @param graph1 [Graphviz] The subgraph to add key1 to, as a node
# @param key1 [Symbol] The key used to find the value that will be used as a node name when added to graph1
# @param graph2 [Graphviz] The subgraph to add key2 to, as a node
# @param key2 [Symbol] The key used to find the value that will be used as a node name when added to graph2
def generate_associations(parent, data, graph1, key1, graph2, key2)
  map_object(data, key1, key2).each do |entry|
    graph1.add_nodes(entry[:item1])
    graph2.add_nodes(entry[:item2])
    parent.add_edges(entry[:item1], entry[:item2])
  end
end

# Plucks key-value pairs from data and returns a unique list
# In the case of this project, it this method is used to make unique associations between nodes and edges
# @param data [Array] An array of hashes, each hash is one record returned from the executeSQLQuery response
# @param key1 [String] A key to look for in each hash inside data and to return
# @param key2 [String] A key to look for in each hash inside data and to return
# @return [Array] An array of hashes containing only the key-value pairs for key1 and key2
def map_object(data, key1, key2)
  data.map { |element| { item1: element[key1].to_s, item2: element[key2].to_s } }.uniq
end
