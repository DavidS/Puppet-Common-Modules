# nagios.pp - everything nagios related
# Copyright (C) 2007 David Schmitt <david@schmitt.edv-bus.at>
# See LICENSE for the full license granted to you.


# the directory containing all nagios configs:
$nagios_cfgdir = "/var/lib/puppet/modules/nagios"
modules_dir{ nagios: }

# The main nagios monitor class
class nagios2 {
	include apache

	package {
		[ nagios2, "nagios-plugins-standard" ]:
			ensure => installed,
	}

	service {
		nagios2:
			ensure => running,
			# Current Debian/etch pattern
			pattern => "/usr/sbin/nagios2 -d /etc/nagios2/nagios.cfg",
			subscribe => File [ $nagios_cfgdir ]
	}

	file {
		# Set a password for the nagiosadmin in the webinterface
		"/etc/nagios2/htpasswd.users":
			source => "puppet://$servername/nagios/htpasswd.users",
			mode => 0640, owner => root, group => www-data;
		# disable default debian configurations
		[ "/etc/nagios2/conf.d/localhost_nagios2.cfg",
		  "/etc/nagios2/conf.d/extinfo_nagios2.cfg",
		  "/etc/nagios2/conf.d/services_nagios2.cfg" ]:
			ensure => absent,
			notify => Service[nagios2];
		"/etc/nagios2/conf.d/hostgroups_nagios2.cfg":
			source => "puppet://$servername/nagios/hostgroups_nagios2.cfg",
			mode => 0644, owner => root, group => www-data,
			notify => Service[nagios2];
		# permit external commands from the CGI
		"/var/lib/nagios2":
			ensure => directory, mode => 751,
			owner => nagios, group => nagios,
			notify => Service[nagios2];
		"/var/lib/nagios2/rw":
			ensure => directory, mode => 2710,
			owner => nagios, group => www-data,
			notify => Service[nagios2];
	}

	# TODO: these are not very robust!
	replace {
		# Debian installs a default check for the localhost. Since VServers
		# usually have no localhost IP, this fixes the definition to check the
		# real IP
		fix_default_config:
			file => "/etc/nagios2/conf.d/localhost_nagios2.cfg",
			pattern => "address *127.0.0.1",
			replacement => "address $ipaddress",
			notify => Service[nagios2];
		# enable external commands from the CGI
		enable_extcommands:
			file => "/etc/nagios2/nagios.cfg",
			pattern => "check_external_commands=0",
			replacement => "check_external_commands=1",
			notify => Service[nagios2];
		# put a cap on service checks
		cap_service_checks:
			file => "/etc/nagios2/nagios.cfg",
			pattern => "max_concurrent_checks=0",
			replacement => "max_concurrent_checks=30",
			notify => Service[nagios2];
	}

	line { include_cfgdir:
		file => "/etc/nagios2/nagios.cfg",
		line => "cfg_dir=$nagios_cfgdir",
		notify => Service[nagios2],
	}

	munin::plugin {
		nagios_hosts: script_path => "/usr/local/bin";
		nagios_svc: script_path => "/usr/local/bin";
		nagios_perf_hosts: ensure => nagios_perf_, script_path => "/usr/local/bin";
		nagios_perf_svc: ensure => nagios_perf_, script_path => "/usr/local/bin";
	}
	file { "/etc/munin/plugin-conf.d/nagios":
		content => "[nagios_*]\nuser root\n",
		mode => 0655, owner => root, group => root,
		notify => Service[munin-node]
	}

	# import the various definitions
	File <<| tag == 'nagios' |>>

	define command($command_line) {
		file { "$nagios_cfgdir/${name}_command.cfg":
				ensure => present, content => template( "nagios/command.erb" ),
				mode => 644, owner => root, group => root,
				notify => Service[nagios2],
		}
	}

	nagios2::command {
		# from ssh.pp
		ssh_port:
			command_line => '/usr/lib/nagios/plugins/check_ssh -p $ARG1$ $HOSTADDRESS$';
		# from apache2.pp
		http_port:
			command_line => '/usr/lib/nagios/plugins/check_http -p $ARG1$ -H $HOSTADDRESS$ -I $HOSTADDRESS$';
		# from bind.pp
		nameserver: command_line => '/usr/lib/nagios/plugins/check_dns -H www.edv-bus.at -s $HOSTADDRESS$';
		# TODO: debug this, produces copious false positives:
		# check_dig2: command_line => '/usr/lib/nagios/plugins/check_dig -H $HOSTADDRESS$ -l $ARG1$ --record_type=$ARG2$ --expected_address=$ARG3$ --warning=2.0 --critical=4.0';
		check_dig2: command_line => '/usr/lib/nagios/plugins/check_dig -H $HOSTADDRESS$ -l $ARG1$ --record_type=$ARG2$'
	}

	define host($ip = $fqdn, $short_alias = $fqdn) {
		@@file {
			"$nagios_cfgdir/${name}_host.cfg":
				ensure => present, content => template( "nagios/host.erb" ),
				mode => 644, owner => root, group => root,
				tag => 'nagios'
		}
	}

	define service($check_command = '', 
		$nagios2_host_name = $fqdn, $nagios2_description = '')
	{
		# this is required to pass nagios' internal checks:
		# every service needs to have a defined host
		include nagios2::target
		$real_check_command = $check_command ? {
			'' => $name,
			default => $check_command
		}
		$real_nagios2_description = $nagios2_description ? {
			'' => $name,
			default => $nagios2_description
		}
		@@file {
			"$nagios_cfgdir/${nagios2_host_name}_${name}_service.cfg":
				ensure => present, content => template( "nagios/service.erb" ),
				mode => 644, owner => root, group => root,
				tag => 'nagios'
		}
	}

	define extra_host($ip = $fqdn, $short_alias = $fqdn, $parent = "none") {
		$nagios_parent = $parent
		file {
			"$nagios_cfgdir/${name}_host.cfg":
				ensure => present, content => template( "nagios/host.erb" ),
				mode => 644, owner => root, group => root,
				notify => Service[nagios2],
		}
	}
	
	# include this class in every host that should be monitored by nagios
	class target {
		nagios2::host { $fqdn: }
		debug ( "$fqdn has $nagios_parent as parent" )
	}

}

