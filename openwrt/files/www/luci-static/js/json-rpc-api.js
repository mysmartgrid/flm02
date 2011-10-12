/**
 * This library allows the web browser to access Luci JSON-RPC API.
 */

/**
 * Saves a Luci form.
 * Field IDs are expected to be adopt the following format: "cdbi.<config>.<section>.<option>".
 * 
 * @form  The form being saved.
 * @goto  The name of the page to go, after form is saved (/cgi-bin/luci/?).
 */
function saveForm(form, goto) {

  try {
    document.body.style.cursor = 'wait';
    
    var auth = login();
    handleError(auth);
    
    for(var i = 0; i < form.elements.length; i++) {
      
      var field = form.elements[i];
        
      if (field.id.indexOf('cbid') == 0) {

        //Form field id informs the parameters: config, section, and option
        var c = field.id.indexOf('.', 5);
        var config = field.id.substring(5, c++);
         
        var s = field.id.indexOf('.', c);
        var section = field.id.substring(c, s++);
        var option = field.id.substring(s);
           
        var id = 'cbid.' + config + '.' + section + '.' + option;
        var value = form.elements[id].value;
           
        response = setOption(auth, config, section, option, value);
        handleError(response);
      }
    }
    
    var response = commit(auth, config);                                 
    handleError(response);
      
  } finally {
    document.body.style.cursor = 'default';
  }
  
  if (goto) {
    window.location = '/cgi-bin/luci/' + goto;
  }
}

function handleError(response) {
  if (response.error != null) {
    throw "JSON-RPC-API Error: " + response.error;
  }
}
  
function login() {
  return postJSON('auth', 'login', '"root", "root"');
}

function setOption(auth, config, section, option, value) {
  return postJSON('uci', 'set', '"' + config + '", "' + section + '", "' + option + '", "' + value + '"', auth); 
}
  
function commit(auth, config) {
  return postJSON('uci', 'commit', '"' + config + '"', auth);
}

function scanWifi(auth, interface) {                                                                                
  return postJSON('sys', 'wifi.iwscan', '"' + interface + '"', auth);                                                            
} 

function getOption(auth, config, section, option) {
  return postJSON('uci', 'get', '"' + config + '", "' + section + '", "' + option + '"', auth);
}
  
function getAllOptions(auth, config) {
  return postJSON('uci', 'get_all', '"' + config + '"', auth);
}

function postJSON(lib, method, params, auth) {

  var url = "/cgi-bin/luci/rpc/" + lib;
  var body = '"method": "' + method + '", "params": [' + params + ']';
    
  if (auth) {
    url += '?auth=' + auth.result;
    body += ', "id": ' + auth.id;
  }
  body = '{' + body + '}';

  var http = new XMLHttpRequest();
  http.open('POST', url, false);
  http.setRequestHeader("Content-type", "application/json");
  http.send(body);
   
  if (http.readyState == 4 && http.status == 200) {
    return eval("(" + http.responseText + ')');
      
  } else {
    return {error: 'Error: state: ' + http.readyState + ', status: ' + http.status  + ',  msg: ' + http.responseText};
  } 
}

function setupJsonRPC() {
  var form = document.forms[0];
  
  //For instance, only the wizard forms
  if (form.action.indexOf('lan') > 0) {
    
    form.action = "javascript: saveForm(document.forms[0], 'msg_wizard');";
  }
}
       
