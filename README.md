# cucm-dial-plan-map
Generates a Graphviz PDF based off of CUCM Dial Plan Query

## System Dependencies
```
ruby - https://rvm.io/
```

## Gem Dependencies
```
gem install savon
gem install ruby-graphviz
gem install ipaddress
```

## Usage
```Command:
  ruby dial_plan_map.rb [OPTIONS]

Options:
  --help
    Show the help dialog

  --ip_address
    Required: Defines the IP address of the Call Manager

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

```
## Example Output
![Alt text](example.png?raw=true "Example")
