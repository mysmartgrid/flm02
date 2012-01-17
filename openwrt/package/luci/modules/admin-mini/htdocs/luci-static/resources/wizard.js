step = "interface";
iface = "";
auth = "";
wifi_section = "";
wifis = [];
login_task = new Array();
counter = 0;

function Sync (counter, task) {
	this.counter = counter;
	this.task = task;
	this.run = function() {
		this.counter--;
		if ( this.counter <= 0 )
			this.task();
	}
}

$(function() {
	load_iface();
	$('#msg_wizard-sensor').find('input[type="checkbox"]').bind('change', function() {toggle_sensor_config(this);});
});

login_callback = function(data, username, password) {
	if (data["result"] != null && data["error"] == null)
	{
		auth = data["result"];
		while ( login_task.length > 0 )
		{
			login_task.pop()();
		}
		$('#login_form_div').overlay().close();
	}
	else
	{
		if (username != null && password != null)
		{
			jsonRequest(
				"/cgi-bin/luci/rpc/auth",
				"login",
				'["' + username + '", "' + password + '"]',
				100,
				function(data) {
					login_callback(data);
				}
			);
		} else {
			show_login_form();
		}
	}
}

login = function(jsonCall)
{
	jsonRequest(
		"/cgi-bin/luci/rpc/auth",
		"login",
		'["root", "root"]',
		100,
		function(data) {
			login_task.push(jsonCall);
			login_callback(data);
		}
	);
}

jsonRequest = function(url, method, params, id, callback, error, timeout)
{
	if (!timeout)
		timeout = 60000;
	// the following does not work due to invalid cookies
	//var auth = new RegExp('(?:^|; )sysauth=([^;]*)').exec(document.cookie);
	//if (!auth)
	//	auth = legacy_auth;
		
	$.ajax({
		'type': "POST",
		'data': '{"method": "' + method + '", "params": ' + params + ', "id": ' + id + '}',
		'dataType': 'json',
		'url': url + "?auth=" + auth,
		'success': callback,
		'error': function(jqXHR, textStatus, errorThrown) {
			if (errorThrown == "Forbidden")
			{
				login(function() {
					$.ajax({
						'type': "POST",
						'data': '{"method": "' + method + '", "params": ' + params + ', "id": ' + id + '}',
						'dataType': 'json',
						'url': url + "?auth=" + auth,
						'success': callback,
						'error': error,
						'timeout': timeout
					});
				});
			} else
				error(jqXHR, textStatus, errorThrown);
		},
		'timeout': timeout
	});
}

load_iface = function(callback)
{
	$(':input').attr('disabled', true);
	$('#msg_wizard-iface-load').attr('src', '/luci-static/resources/loading.gif');
	//login(function() {
		jsonRequest("/cgi-bin/luci/rpc/uci", "get", '["network", "wan", "ifname"]', 90, function(data) {
			if ( data['result'] == "ath0" )
				$('#msg_wizard_interface').val("wlan");
			else
				$('#msg_wizard_interface').val("lan");

			$('#msg_wizard-iface-load').attr('src', '/luci-static/resources/ok.png');
			$(':input').removeAttr('disabled');
		});
	//});
}

load_wifi = function(callback)
{
	$('#msg_wizard-wifi-config').attr('src', '/luci-static/resources/loading.gif');
	$('#msg_wizard-wifi-list').attr('src', '/luci-static/resources/loading.gif');
	wifi_sync = new Sync(2, function() {
		$(':input').removeAttr('disabled');
		if (callback)
			callback();
	});
	jsonRequest("/cgi-bin/luci/rpc/sys", "wifi.iwscan", '["ath0"]', "99", function(data) { 
		var options;
		for ( var k = 0; k < data.result.length; k++ )
		{
			if ( data.result[k].ESSID != "" )
			{
				options += '<option class="tmp_essid" value="' + data.result[k].ESSID + '">' + data.result[k].ESSID + '</option>';
				wifis.push(data.result[k]);
			}
		}
		if ( data.result.length > 0 )
		{
			$('#essid').prepend(options);
		}
		$('#msg_wizard-wifi-list').attr('src', "/luci-static/resources/ok.png");
		wifi_sync.run();
	}, function(jqXHR, textStatus, errorThrown) {
		$('#msg_wizard-wifi-list').attr('src', "/luci-static/resources/fail.png");
		$('#msg_wizard-wifi-list').parent().append('<div class="errorbox apiError">' + textStatus + ': ' + errorThrown + '</div>');
	});
	jsonRequest("/cgi-bin/luci/rpc/uci", "get_all", '["wireless"]', "102", function(data) {
		var ssid, enc, key;
		if ( wifi_section == "" )
		{
			for ( tmpKey in data.result )
			{
				if (data.result[tmpKey].ssid)
				{
					wifi_section = tmpKey;
				}
			}
		}
		ssid = data.result[wifi_section].ssid;
		enc = data.result[wifi_section].encryption;
		key = data.result[wifi_section].key;

		present = $('.tmp_essid');
		var custom = true;
		for ( var k = 0; k < present.length; k++ )
		{
			if ( present[k].value == ssid )
				custom = false;
		}
		if ( custom )
		{
			$('#essid').val('');
			$('#essid-input-div').show();
			$('#essid-input').val(ssid);
			change_wifi();
		} else {
			$('#essid').val(ssid);
			$('#essid-input-div').hide();
		}
		$('#wifi-enc-input').val(enc);
		$('#wifi-key-input').val(key);
		$('#msg_wizard-wifi-config').attr('src', "/luci-static/resources/ok.png");
		wifi_sync.run();
	}, function(jqXHR, textStatus, errorThrown) {
		$('#msg_wizard-wifi-config').attr('src', "/luci-static/resources/fail.png");
		$('#msg_wizard-wifi-config').parent().append('<div class="errorbox apiError">' + textStatus + ': ' + errorThrown + '</div>');
	});
}

load_network = function(callback)
{
	$('#msg_wizard-net-config').attr('src', '/luci-static/resources/loading.gif');
	jsonRequest("/cgi-bin/luci/rpc/uci", "get_all", '["network", "wan"]', "103", function(data)
		{
			$('#network-ipaddr').val(data.result.ipaddr);
			$('#network-netmask').val(data.result.netmask);
			$('#network-gateway').val(data.result.gateway);
			$('#network-dns').val(data.result.dns);
			if ( data.result.proto == "dhcp" )
			{
				$('#dhcp').prop('checked', true);
				$('#network-wan-ipaddr').hide();
				$('#network-wan-netmask').hide();
				$('#network-wan-gateway').hide();
				$('#network-wan-dns').hide();
			}
			else
			{
				$('#dhcp').prop('checked', false);
				$('#network-wan-ipaddr').show();
				$('#network-wan-netmask').show();
				$('#network-wan-gateway').show();
				$('#network-wan-dns').show();
			}
			$('#msg_wizard-net-config').attr('src', '/luci-static/resources/ok.png');
			$(':input').removeAttr('disabled');
			if ( callback )
				callback();
		}, function(jqXHR, textStatus, errorThrown) {
			$('#msg_wizard-net-config').attr('src', "/luci-static/resources/fail.png");
			$('#msg_wizard-net-config').parent().append('<div class="errorbox apiError">' + textStatus + ': ' + errorThrown + '</div>');
		}
	);
}

load_sensor_config = function(callback)
{
	$('.sensor-value').empty();
	$('#msg_wizard-sensor-load').attr('src', "/luci-static/resources/loading.gif");
	jsonRequest("/cgi-bin/luci/rpc/uci", "get_all", '["flukso"]', "110", function(data)
	{
		$('#flukso-sensor-phases').val(data["result"]["main"]["phase"]);
		if ( data["result"]["main"]["phase"] == "3" )
		{
			$('#cbi-flukso-2').hide();
			$('#cbi-flukso-3').hide();
		} else {
			$('#cbi-flukso-2').show();
			$('#cbi-flukso-3').show();
		}
		for(var k = 1; k <= data["result"]["main"]["max_sensors"]; k++)
		{
			if ( data["result"][k]["enable"] == "1" )
			{
				$('#cbi-flukso-' + k + '-enable').find('input').prop('checked', true);
				toggle_sensor_config($('#cbi-flukso-' + k + '-enable').find('input'));
			} else {
				$('#cbi-flukso-' + k + '-enable').find('input').prop('checked', false);
				toggle_sensor_config($('#cbi-flukso-' + k + '-enable').find('input'));
			}
			//set sensor id
			$('#cbi-flukso-' + k + '-id').find('input').val(data["result"][k]["id"]);
			$('#cbi-flukso-' + k + '-id').find('div.sensor-value').append(data["result"][k]["id"]);
			//set sensor class
			$('#cbi-flukso-' + k + '-class').find('input').val(data["result"][k]["class"]);
			$('#cbi-flukso-' + k + '-class').find('div.sensor-value').append(data["result"][k]["class"]);
			if ( data["result"][k]["class"] != "uart" )
			{
				//set sensor function
				$('#cbi-flukso-' + k + '-function').find('input').val(data["result"][k]["function"]);

				if ( data["result"][k]["class"] == "analog" )
				{
					//set sensor type
					$('#cbi-flukso-' + k + '-type').find('input').val(data["result"][k]["type"]);
					$('#cbi-flukso-' + k + '-type').find('div.sensor-value').append(data["result"][k]["type"]);
					//set sensor voltage
					$('#cbi-flukso-' + k + '-voltage').find('input').val(data["result"][k]["voltage"]);
					//set sensor current
					$('#cbi-flukso-' + k + '-current').find('input').val(data["result"][k]["current"]);
				} else {
					//set sensor type
					$('#cbi-flukso-' + k + '-type').find('select').val(data["result"][k]["type"]);
					if ( data["result"][k]["type"] == "electricity" )
					{
						//set sensor imppkwh
						$('#cbi-flukso-' + k + '-imppkwh').find('input').val(data["result"][k]["imppkwh"]);
						if ( data["result"][k]["enable"] == "1" )
						{
							$('#cbi-flukso-' + k + '-lpimp').hide();
							$('#cbi-flukso-' + k + '-imppkwh').show();
						}
					} else {
						//set sensor lpimp
						$('#cbi-flukso-' + k + '-lpimp').find('input').val(data["result"][k]["lpimp"]);
						if ( data["result"][k]["enable"] == "1" )
						{
							$('#cbi-flukso-' + k + '-imppkwh').hide();
							$('#cbi-flukso-' + k + '-lpimp').show();
						}
					}
				}
			}
		};
		window.lang.run();
		$('#msg_wizard-sensor-load').attr('src', '/luci-static/resources/ok.png');
		if(callback)
			callback();
	}, function(jqXHR, textStatus, errorThrown) {
		$('#msg_wizard-sensor-load').attr('src', "/luci-static/resources/fail.png");
		$('#msg_wizard-sensor-load').parent().append('<div class="errorbox apiError">' + textStatus + ': ' + errorThrown + '</div>');
	});
}

select_enc = function(essid)
{
	for (var k = 0; k < wifis.length; k++)
	{
		if (wifis[k].ESSID == essid)
		{
			if(wifis[k]['Encryption key'] != 'on')
				return 'none';
			else if (wifis[k]['IE'] == 'WPA Version 1')
				return 'psk';
			else if (wifis[k]['IE'] == 'IEEE 802.11i/WPA2 Version 1')
				return 'psk2';
			else
				return 'wep';
		}
	}
			return $('#wifi-enc-input').val();
}

save_iface = function(callback)
{
	$('#msg_wizard-net-iface-set').attr('src', "/luci-static/resources/loading.gif");
	$('#msg_wizard-wifi-iface-set').attr('src', "/luci-static/resources/loading.gif");
	fwzone = "";
	iface_sync = new Sync(2, function() {
		if ( $('#msg_wizard_interface').val() == "wlan" )
		{
			iface_commit_sync = new Sync(5, function() {
				jsonRequest("/cgi-bin/luci/rpc/uci", "commit", '["firewall"]', "96", function(data) {});
				jsonRequest("/cgi-bin/luci/rpc/uci", "commit", '["network"]', "97", function(data) {});
				jsonRequest("/cgi-bin/luci/rpc/uci", "commit", '["wireless"]', "98", function(data) {});
				$('#msg_wizard-wifi-iface-set').attr('src', "/luci-static/resources/ok.png");
				if ( callback )
					callback();
			});
			jsonRequest("/cgi-bin/luci/rpc/uci", "set", '["firewall", ' + JSON.stringify(fwzone) + ', "input", "REJECT"]', "91", function(data) {iface_commit_sync.run();});
			jsonRequest("/cgi-bin/luci/rpc/uci", "set", '["network", "wan", "ifname", "ath0"]', "92", function(data) {iface_commit_sync.run();});
			jsonRequest("/cgi-bin/luci/rpc/uci", "tset", '["network", "lan", ' + JSON.stringify({"ifname": "eth0", "ipaddr": "192.168.255.1", "netmask": "255.255.255.0", "proto": "static"}) + ']', "93", function(data) {iface_commit_sync.run();});
			jsonRequest("/cgi-bin/luci/rpc/uci", "set", '["wireless", "wifi0", "disabled", "0"]', "94", function(data) {iface_commit_sync.run();});
			jsonRequest("/cgi-bin/luci/rpc/uci", "tset", '["wireless", ' + JSON.stringify(wifi_section) + ', ' + JSON.stringify({"network": "wan", "mode": "sta"}) + ']', "95", function(data) {iface_commit_sync.run();});
		} else {
			iface_commit_sync = new Sync(5, function() {
				jsonRequest("/cgi-bin/luci/rpc/uci", "commit", '["firewall"]', "96", function(data) {});
				jsonRequest("/cgi-bin/luci/rpc/uci", "commit", '["network"]', "97", function(data) {});
				jsonRequest("/cgi-bin/luci/rpc/uci", "commit", '["wireless"]', "98", function(data) {});
				$('#msg_wizard-net-iface-set').attr('src', "/luci-static/resources/ok.png");
				if ( callback )
					callback();
			});
			jsonRequest("/cgi-bin/luci/rpc/uci", "set", '["firewall", ' + JSON.stringify(fwzone) + ', "input", "ACCEPT"]', "91", function(data) {iface_commit_sync.run();});
			jsonRequest("/cgi-bin/luci/rpc/uci", "set", '["network", "wan", "ifname", "eth0"]', "92", function(data) {iface_commit_sync.run();});
			jsonRequest("/cgi-bin/luci/rpc/uci", "set", '["network", "lan", "ifname", "ath0"]', "93", function(data) {iface_commit_sync.run();});
			jsonRequest("/cgi-bin/luci/rpc/uci", "set", '["wireless", "wifi0", "disabled", "1"]', "94", function(data) {iface_commit_sync.run();});
			jsonRequest("/cgi-bin/luci/rpc/uci", "tset", '["wireless", ' + JSON.stringify(wifi_section) + ', ' + JSON.stringify({"network": "lan", "mode": "ap"}) + ']', "95", function(data) {iface_commit_sync.run();});
		}
	});
	jsonRequest("/cgi-bin/luci/rpc/uci", "get_all", '["firewall"]', "80", function(data) {
		for ( tmpKey in data.result )
		{
			if ( data.result[tmpKey].name == "wan" )
				fwzone = tmpKey;
		}
		iface_sync.run();
	});
	jsonRequest("/cgi-bin/luci/rpc/uci", "get_all", '["wireless"]', "81", function(data) {
		if ( wifi_section == "" )
		{
			for ( tmpKey in data.result )
			{
				if ( data.result[tmpKey].ssid )
					wifi_section = tmpKey;
			}
		};
		iface_sync.run();
	});
}

save_wifi = function(callback)
{
	$('#msg_wizard-wifi-save').attr('src', '/luci-static/resources/loading.gif');
	var ssid, enc, key;
	if ( $('#essid').val() == '' )
		ssid = $('#essid-input').val();
	else
		ssid = $('#essid').val();

	if ( $('#autoenc').prop('checked') == true )
		enc = select_enc(ssid);
	else
		enc = $('#wifi-enc-select').val();

	if ( enc == "none" )
		key = "";
	else
		key = $('#wifi-key-input').val();

	jsonRequest("/cgi-bin/luci/rpc/uci", "tset", '["wireless", ' + JSON.stringify(wifi_section) + ', ' + JSON.stringify({"ssid": ssid , "encryption": enc, "key": key}) + ']', "104", function(data) {
		jsonRequest("/cgi-bin/luci/rpc/uci", "commit", '["wireless"]', "105", function(data) {
			$('#msg_wizard-wifi-save').attr('src', '/luci-static/resources/ok.png');
			callback();
		}, function(jqXHR, textStatus, errorThrown) {
			$('#msg_wizard-wifi-save').attr('src', "/luci-static/resources/fail.png");
			$('#msg_wizard-wifi-save').parent().append('<div class="errorbox apiError">' + textStatus + ': ' + errorThrown + '</div>');
		});
	}, function(jqXHR, textStatus, errorThrown) {
		$('#msg_wizard-wifi-save').attr('src', "/luci-static/resources/fail.png");
		$('#msg_wizard-wifi-save').parent().append('<div class="errorbox apiError">' + textStatus + ': ' + errorThrown + '</div>');
	});
}

save_network = function(callback)
{
	$('#msg_wizard-net-save').attr('src', '/luci-static/resources/loading.gif');
	$('#msg_wizard-net-apply').attr('src', '/luci-static/resources/loading.gif');
	var section, config;
	/*if ( iface == "wifi" )
		section = "wan";
	else
		section = "lan";*/

	if ( $('#dhcp').prop('checked') == true )
		config = {'proto': 'dhcp'};
	else
	{
		config = {'proto': 'static', 'ipaddr': $('#network-ipaddr').val(), 'netmask': $('#network-netmask').val(), 'gateway': $('#network-gateway').val(), 'dns': $('#network-dns').val()};
	}

	jsonRequest("/cgi-bin/luci/rpc/uci", "tset", '["network", "wan", ' + JSON.stringify(config) + ']', "106", function(data) {
		jsonRequest("/cgi-bin/luci/rpc/uci", "commit", '["network"]', "107", function(data) {
			$('#msg_wizard-net-save').attr('src', '/luci-static/resources/ok.png');
			if(callback)
				callback();
		}, function(jqXHR, textStatus, errorThrown) {
			$('#msg_wizard-net-save').attr('src', "/luci-static/resources/fail.png");
			$('#msg_wizard-net-save').parent().append('<div class="errorbox apiError">' + textStatus + ': ' + errorThrown + '</div>');
		});
	}, function(jqXHR, textStatus, errorThrown) {
		$('#msg_wizard-net-save').attr('src', "/luci-static/resources/fail.png");
		$('#msg_wizard-net-save').parent().append('<div class="errorbox apiError">' + textStatus + ': ' + errorThrown + '</div>');
	});
}

//TODO: add more error entries
errorsMap = {                                                                                                         
	"\.\*\\sok\\n$": 'ok',                                                                                              
							"\.\*Name\\sor\\sservice\\snot\\sknown\.\*": 'The mySmartGrid server is unreachable. Please check your network configuration',
			}

checkFsyncResult = function(result) {                                                                                   
																																																																								
	var message = 'Unknown';
	var ok = true;
	$.each(errorsMap, function(exp, formatted) {                                                                  
		if ((new RegExp(exp)).test(result)) {
			message = formatted;
			ok = false;
			return false;//Stop searching
		}
	});
	return {'ok' : ok, 'message': message};
}

save_sensors = function(callback)
{
	$('#msg_wizard-sensor-save').attr('src', '/luci-static/resources/loading.gif');
	$('#msg_wizard-sensor-apply').attr('src', '/luci-static/resources/loading.gif');
	config = {};
	$('.sensor-config').each(function(index, element) {
		var k = index + 1;
		var sensor = {};
		sensor['.name'] = k;
		sensor['id'] = $(element).find('#flukso-' + k + '-id').val();
		sensor['enable'] = $(element).find('#flukso-' + k + '-enable').prop('checked') ? "1" : "0";
		sensor['class'] = $(element).find('#flukso-' + k + '-class').val();
		if ( $(element).find('#flukso-' + k + '-class').val() != 'uart' )
		{
			sensor['type'] = $(element).find('#flukso-' + k + '-type').val();
			sensor['function'] = $(element).find('#flukso-' + k + '-function').val();
			if ( $(element).find('#flukso-' + k + '-class').val() == 'analog' )
			{
				sensor['voltage'] = $(element).find('#flukso-' + k + '-voltage').val();
				sensor['current'] = $(element).find('#flukso-' + k + '-current').val();
			} else {
				if ( $(element).find('#flukso-' + k + '-type').val() == 'electricity' )
				{
					sensor['imppkwh'] = $(element).find('#flukso-' + k + '-imppkwh').val();
				} else {
					sensor['lpimp'] = $(element).find('#flukso-' + k + '-lpimp').val();
				}
			}
		}
		config[k] = sensor;
	});
	if ( $('#flukso-sensor-phases').val() == 1 )
	{
		config[1]['port'] = ["1"];
		config[2]['port'] = ["2"];
		config[3]['port'] = ["3"];
		config['main'] = {'phase': "1"};
	} else {
		config[1]['port'] = ["1", "2", "3"];
		config[2]['port'] = "";
		config[2]['enable'] = "0"; //make sure to disable sensor 2
		config[3]['port'] = "";
		config[3]['enable'] = "0"; //make sure to disable sensor 3
		config['main'] = {'phase': "3"};
	}

	//TODO: adapt this function to be used in other places
	handleSensorApplyError = function(jqXHR, textStatus, errorThrown) {                                         
		$('#msg_wizard-sensor-apply').attr('src', "/luci-static/resources/fail.png"); 
		$('#msg_wizard-sensor-apply').parent().append('<div class="errorbox apiError">' + textStatus + ': ' + errorThrown + '</div>');
	}

	sensor_sync = new Sync(7, function() {
		jsonRequest("/cgi-bin/luci/rpc/uci", "commit", '["flukso"]', "109", function(data) {
			$('#msg_wizard-sensor-save').attr('src', '/luci-static/resources/ok.png');
			jsonRequest("/cgi-bin/luci/rpc/sys", "exec", '["fsync"]', "109", function(data) {
			
				var check = checkFsyncResult(data.result);                                                 
		
				if (check.ok) {
					$('#msg_wizard-sensor-apply').attr('src', '/luci-static/resources/ok.png');
					if(callback)
						callback();
				} else {
					handleSensorApplyError(null, 'Failure', check.message);
					$('#wizard-form-buttons').find(':reset').removeAttr('disabled');
				}
				
			}, handleSensorApplyError)

		}, function(jqXHR, textStatus, errorThrown) {
			$('#msg_wizard-sensor-save').attr('src', "/luci-static/resources/fail.png");
			$('#msg_wizard-sensor-save').parent().append('<div class="errorbox apiError">' + textStatus + ': ' + errorThrown + '</div>');
		});
	});

	jsonRequest("/cgi-bin/luci/rpc/uci", "tset", '["flukso", "1", ' + JSON.stringify(config[1]) + ']', "108", function(data) { sensor_sync.run(); });
	jsonRequest("/cgi-bin/luci/rpc/uci", "tset", '["flukso", "2", ' + JSON.stringify(config[2]) + ']', "108", function(data) { sensor_sync.run(); });
	jsonRequest("/cgi-bin/luci/rpc/uci", "tset", '["flukso", "3", ' + JSON.stringify(config[3]) + ']', "108", function(data) { sensor_sync.run(); });
	jsonRequest("/cgi-bin/luci/rpc/uci", "tset", '["flukso", "4", ' + JSON.stringify(config[4]) + ']', "108", function(data) { sensor_sync.run(); });
	jsonRequest("/cgi-bin/luci/rpc/uci", "tset", '["flukso", "5", ' + JSON.stringify(config[5]) + ']', "108", function(data) { sensor_sync.run(); });
	jsonRequest("/cgi-bin/luci/rpc/uci", "tset", '["flukso", "6", ' + JSON.stringify(config[6]) + ']', "108", function(data) { sensor_sync.run(); });
	jsonRequest("/cgi-bin/luci/rpc/uci", "tset", '["flukso", "main", ' + JSON.stringify(config['main']) + ']', "108", function(data) { sensor_sync.run(); });
}

progress_bar = function(step)
{
	if (step == "network")
	{
		$('#prog-network').css('background-image', 'url("/luci-static/resources/progressbar_cur.png")');
		$('#prog-sensor').css('background-image', 'url("/luci-static/resources/progressbar.png")');
		$('#prog-reg').css('background-image', 'url("/luci-static/resources/progressbar.png")');
	} else if (step == "sensors") {
		$('#prog-network').css('background-image', 'url("/luci-static/resources/progressbar_done.png")');
		$('#prog-sensor').css('background-image', 'url("/luci-static/resources/progressbar_cur.png")');
		$('#prog-reg').css('background-image', 'url("/luci-static/resources/progressbar.png")');
	} else if (step == "registration") {
		$('#prog-network').css('background-image', 'url("/luci-static/resources/progressbar_done.png")');
		$('#prog-sensor').css('background-image', 'url("/luci-static/resources/progressbar_done.png")');
		$('#prog-reg').css('background-image', 'url("/luci-static/resources/progressbar_cur.png")');
	}
}

submit = function()
{
	$('.apiError').detach();
	$(':input').attr('disabled', true);
	if ( step == "interface" )
	{
		if ( $('#msg_wizard_interface').val() == "wlan" )
		{
			save_iface(function() {
				load_wifi()
			});
			step = "wifi";
			iface = "wifi";
			$("#msg_wizard").hide(20, function() { $("#msg_wifi").show(); } );
			$("#msg_wizard-net-iface-set-div").hide();
			$("#msg_wizard-wifi-iface-set-div").show();
		} else {
			save_iface(function() {
				load_network()
			});
			iface = "lan";
			step = "network";
			$("#msg_wizard-wifi-save-div").hide();
			$("#msg_wizard").hide(20, function() { $("#network").show(); } );
			$("#msg_wizard-net-iface-set-div").show();
			$("#msg_wizard-wifi-iface-set-div").hide();
		}
		$("#wizard-form-buttons").find(':reset').show();
		progress_bar("network");
	}
	else if ( step == "wifi" )
	{
		submit_sync = new Sync(2, function()
		{
			$(':input').removeAttr('disabled');
		});
		save_wifi(submit_sync.run),
		load_network(submit_sync.run)
		step = "network";
			$("#msg_wizard-wifi-save-div").show();
		$("#msg_wifi").hide(20, function() { $("#network").show(); } );
		progress_bar("network");
	}
	else if ( step == "network" )
	{
		submit_sync = new Sync(3, function()
		{
			$(':input').removeAttr('disabled');
		});
		step = "sensor";
		load_sensor_config(function() {submit_sync.run();});
		save_network(
			function() {
				submit_sync.run();
				jsonRequest("/cgi-bin/luci/rpc/uci", "apply", '["network", "wireless"]', "108", function(data) {});
				window.setTimeout(poll_device(function() {submit_sync.run();}), 10000);
			}
		);
		//$("#form-buttons").hide();
		progress_bar("sensors");
		$("#network").hide();
		$("#msg_wizard-sensor").show();
	}
	else if ( step == "sensor" )
	{
		sync_task = function()
		{
			$(':input').removeAttr('disabled');
		}
		step = "registration";
		save_sensors(sync_task);
		progress_bar("registration");
		$("#msg_wizard-sensor").hide();
		$("#msg_wizard-registration").show();
		$("#wizard-form-buttons").find(":submit").hide();
	}
}

wizard_reset = function()
{
	$('.apiError').detach();
	$('.tmp_essid').detach();
	if ( step == "wifi" )
	{
		$("#msg_wifi").hide(20, function() { $("#msg_wizard").show(); } );
		step = "interface";
		progress_bar("network");
		$("#wizard-form-buttons").find(':reset').hide();
	}
	else if ( step == "network" )
	{
		if ( iface == "wifi" )
		{
			load_wifi();
			$("#network").hide(20, function() { $("#msg_wifi").show(); } );
			step = "wifi";
		}
		else
		{
			$("#network").hide(20, function() { $("#msg_wizard").show(); } );
			step = "interface";
			$("#wizard-form-buttons").find(':reset').hide();
		}
		progress_bar("network");
	}
	else if ( step == "sensor" )
	{
		$('#msg_wizard-sensor').hide(20, function() { $("#network").show(); } );
		step = "network";
		progress_bar("network");
	}
	else if ( step == "registration" )
	{
		load_sensor_config(function() { $(':input').removeAttr('disabled') });
		$('#msg_wizard-registration').hide(20, function() { $("#msg_wizard-sensor").show(); } );
		step = "sensor";
		progress_bar("sensors");
		$("#wizard-form-buttons").find(':submit').show();
	}
}

toggle_dhcp = function()
{
	if ( $('#dhcp').prop('checked') )
	{
		$('#network-wan-ipaddr').hide();
		$('#network-wan-netmask').hide();
		$('#network-wan-gateway').hide();
		$('#network-wan-dns').hide();
	}
	else
	{
		$('#network-wan-ipaddr').show();
		$('#network-wan-netmask').show();
		$('#network-wan-gateway').show();
		$('#network-wan-dns').show();
	}
}

poll_device = function(callback)
{
	$('#msg_wizard-net-apply').attr('src', '/luci-static/resources/loading.gif');
	$.ajax({
		'type': "POST",
		'data': '{"method": "login", "params": "["root", "root"]", "id": "200"}',
		'dataType': 'json',
		'url': "/cgi-bin/luci/rpc/auth",
		'success': function(data) {
				$('#msg_wizard-net-apply').attr('src', '/luci-static/resources/ok.png');
				if (callback)
					callback();
			},
		'timeout': 5000,
		'error': function(jqXHR, textStatus, errorThrown) {
				if (textStatus == "timeout")
					poll_device(callback);
				else if (callback)
					callback();
			}
	});
}

show_login_form = function()
{
	$('#login_form_div').find(':input').removeAttr('disabled');
	$('#login_form_div').overlay({
		mask: {
			color: '#fff',
			loadSpeed: 200,
			opacity: 0.5
		},
		closeOnClick: false,
		load: true //load overlay on first call
	}).load(); //load overlay on every call except the first one
	$('#password').focus();
}

toggle_sensor_config = function(config)
{
	if ( $(config).prop('checked') )
	{
		var name = $(config).parent().parent().parent().attr('id');
		var k = name[name.length - 1];
		if ( $('#cbi-flukso-' + k + '-class').find('input').val() == "pulse" )
		{
			if ( $('#cbi-flukso-' + k + '-type').find('select').val() == "electricity" )
			{
				$(config).parent().parent().nextUntil('fieldset').not('#cbi-flukso-' + k + '-lpimp').show();
			} else {
				$(config).parent().parent().nextUntil('fieldset').not('#cbi-flukso-' + k + '-imppkwh').show();
			}
		} else {
			$(config).parent().parent().nextUntil('fieldset').show();
		}
	} else {
		$(config).parent().parent().nextUntil('fieldset').hide();
	}
}

toggle_sensor_type = function(config)
{
	var name = $(config).parent().parent().parent().attr('id');
	var k = name[name.length - 1];
	if ( $('#cbi-flukso-' + k + '-type').find('select').val() == "electricity" )
	{
		$('#cbi-flukso-' + k + '-lpimp').hide();
		$('#cbi-flukso-' + k + '-imppkwh').show();
	} else {
		$('#cbi-flukso-' + k + '-imppkwh').hide();
		$('#cbi-flukso-' + k + '-lpimp').show();
	}
}

toggle_phase_setting = function(config)
{
	var setting = $(config).val();
	if ( setting == 1 )
	{
		//$('#flukso-1-enable').prop('checked', true);
		toggle_sensor_config($('#flukso-1-enable'));
		//$('#flukso-2-enable').prop('checked', true);
		toggle_sensor_config($('#flukso-2-enable'));
		//$('#flukso-3-enable').prop('checked', true);
		toggle_sensor_config($('#flukso-3-enable'));
		$('#cbi-flukso-2').show();
		$('#cbi-flukso-3').show();
	} else {
		//$('#flukso-1-enable').prop('checked', true);
		toggle_sensor_config($('#flukso-1-enable'));
		//$('#flukso-2-enable').prop('checked', false);
		toggle_sensor_config($('#flukso-2-enable'));
		//$('#flukso-3-enable').prop('checked', false);
		toggle_sensor_config($('#flukso-3-enable'));
		$('#cbi-flukso-2').hide();
		$('#cbi-flukso-3').hide();
	}
}

change_wifi = function()
{
	if ($('#essid').val() == '')
	{
		$('#essid-input-div').show();
		$('#autoenc').removeAttr('checked');
		$('#wifi-enc').show();
		$('#wifi-key').show();
	} else {
		$('#essid-input-div').hide();

		if ($('#autoenc').prop('checked'))
		{
			$('#wifi-enc').hide();
			var enc = select_enc($('#essid').val());
			$('#wifi-enc-select').val(enc);
			if (enc != 'none')
			{
				$('#wifi-key').show();
			} else {
				$('#wifi-key').hide();
			}
		} else {
			$('#wifi-enc').show();
			if ($('#wifi-enc-select').val() == 'none')
			{
				$('wifi-key').hide();
			} else {
				$('#wifi-key').show();
			}
		}
	}
}

