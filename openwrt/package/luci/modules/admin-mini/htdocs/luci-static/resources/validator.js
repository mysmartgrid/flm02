var lanip = "192.168.255.1";
$(document).ready(function() {
	jsonRequest("/cgi-bin/luci/rpc/uci", "get_all", '["network", "lan"]', "201", function(data)
	{
			lanip = data.result.ipaddr;
	});
	var validator = $("#wizard_form").validate({

		rules: {
			'wifi-key-input': {
				wep: {
					depends: function(element)
					{
						var ssid, enc, key;
						if ( $('#essid').val() == '' )
							ssid = $('#essid-input').val();
						else
							ssid = $('#essid').val();

						if ( $('#autoenc').prop('checked') == true )
							enc = select_enc(ssid);
						else
							enc = $('#wifi-enc-select').val();
						return (enc == 'wep');
					}

				},
				'wep-hex': {
					depends: function(element)
					{
						var ssid, enc, key;
						if ( $('#essid').val() == '' )
							ssid = $('#essid-input').val();
						else
							ssid = $('#essid').val();

						if ( $('#autoenc').prop('checked') == true )
							enc = select_enc(ssid);
						else
							enc = $('#wifi-enc-select').val();
						return ((enc == 'wep') && ($('#wifi-key-input').val().length == 10 || $('#wifi-key-input').val().length == 26));
					}
				},
				wpa: {
					depends: function(element)
					{
						var ssid, enc, key;
						if ( $('#essid').val() == '' )
							ssid = $('#essid-input').val();
						else
							ssid = $('#essid').val();

						if ( $('#autoenc').prop('checked') == true )
							enc = select_enc(ssid);
						else
							enc = $('#wifi-enc-select').val();
						return (enc == 'psk' || enc == 'psk2');
					}
				}

			},
			'network-ipaddr': {
			ip: {
				depends: function(element)
				{
					return !$('#dhcp').prop('checked');
				}
				},
			subnet: true
			},
			'network-netmask': {
			ip: {
				depends: function(element)
				{
					return !$('#dhcp').prop('checked');
				}
			}
			},
			'network-gateway': {
			ip: {
				depends: function(element)
				{
					return $('#network-gateway').val() != '';
				}
			}
			},
			'network-dns': {
			ip: {
				depends: function(element)
				{
					return $('#network-dns').val() != '';
				}
			}
			},
			'flukso-1-function': {
			required: {
				depends: function(element)
				{
					return $('#flukso-1-enable').prop('checked');
				}
			}
			},
			'flukso-2-function': {
			required: {
				depends: function(element)
				{
					return $('#flukso-2-enable').prop('checked');
				}
			}
			},
			'flukso-3-function': {
			required: {
				depends: function(element)
				{
					return $('#flukso-3-enable').prop('checked');
				}
			}
			},
			'flukso-4-function': {
			required: {
				depends: function(element)
				{
					return $('#flukso-4-enable').prop('checked');
				}
			}
			},
			'flukso-5-function': {
			required: {
				depends: function(element)
				{
					return $('#flukso-5-enable').prop('checked');
				}
			}
			}
		},
		messages: {
			'flukso-1-function': "Please specify a sensor function.",
			'flukso-2-function': "Please specify a sensor function.",
			'flukso-3-function': "Please specify a sensor function.",
			'flukso-4-function': "Please specify a sensor function.",
			'flukso-5-function': "Please specify a sensor function.",
			'network-netmask': "Please enter a valid subnet mask."
		},
		showErrors: function(errorMap, errorList) {
			this.defaultShowErrors();
			$('.error').attr('lang', $.cookie('lang'));
			$('.error').attr('lang', 'en');
			window.lang.run();
		}
	});
});
jQuery.validator.addMethod("wep", function(value, element) {
	return (value.length == 5 || value.length == 13 || value.length == 10 || value.length == 26);
}, "Please enter a valid WiFi key.");
jQuery.validator.addMethod("wep-hex", function(value, element) {
	return value.match(/^([0-9]|[a-f]|[A-F])+$/);
}, "Please enter a valid WiFi key.");
jQuery.validator.addMethod("wpa", function(value, element) {
	if ( value.length < 7 || value.length > 64 ) {
		return false;
	}
	else {
		return true;
	}
}, "Please enter a valid WiFi key.");
jQuery.validator.addMethod("ip", function(value, element) {
	return value.match(/^((25[0-5]|2[0-4][0-9]|1[0-9]{2}|[0-9]{1,2})\.){3}(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[0-9]{1,2})$/);
}, "Please enter a valid IP address.");
jQuery.validator.addMethod("subnet", function(value, element) {
		if ( $('#msg_wizard_interface').val() == "lan" ) {
			return true;
		}
		var exp = /^(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[0-9]{1,2})\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[0-9]{1,2})\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[0-9]{1,2})\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[0-9]{1,2})$/;
		ip = exp.exec(value);
		testip = exp.exec(lanip);

		return (value != testip[1] + "." + testip[2] + "." + testip[3] + "." + ip[4]);
}, "The WiFi IP address must not be in the same subnet as the LAN IP address.");
//TODO was passiert wenn man im wizard zurück geht

