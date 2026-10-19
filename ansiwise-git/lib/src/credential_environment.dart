import 'dart:convert';

/// The credential as git takes it without it appearing in any argument: an authorization header,
/// set through git's configuration-by-environment for every address on [host], which is the host
/// with its port where the address names one.
///
/// EMPTY WHERE THERE IS NO CREDENTIAL, which is not the same as an empty one. A header carrying
/// `null:null` would be sent to a server that never asked for one and would be refused by some of
/// them; no header at all is what a public repository is read with.
///
/// Every command of this package that reaches a repository with a credential takes it from here,
/// so the header is one composition and the environment of a command is the only place it stands.
Map<String, String> credentialEnvironment({
  required String host,
  required String? credential,
  required String? credentialUser,
}) => credential == null
    ? const <String, String>{}
    : <String, String>{
        'GIT_CONFIG_COUNT': '1',
        'GIT_CONFIG_KEY_0': 'http.https://$host/.extraHeader',
        'GIT_CONFIG_VALUE_0':
            'Authorization: Basic ${base64Encode(utf8.encode('$credentialUser:$credential'))}',
      };
