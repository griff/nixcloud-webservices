# roadmap
#
# 1. implement the config part, where "ACME" creates a `security.acme` entry &
#    "selfsigned" creates a self signed tls certificate
# 2. integrate this into nixcloud-webservices
# 3. redo all description and examples
# 4. write a comprehensive nixcloud test for this
# 5. release this to be used in nixcloud-webservices and nixcloud.email
# 6. blog about this new feature and give a short introduction into nix typing
#
#
# FIXME: blog post:
#  - example: see the meta.nix example
#  - check: if check for custom type fails, one should be able to get a LOC string, where that type
#    was defined and what arguments it wants (as string for instance) and additionally one should
#    be able to supply a custom error message
#        error: The option value `nixcloud.TLS.certs.example.com.mode' in `/home/joachim/Desktop/projects/nixcloud/nixcloud-webservices/modules/services/TLS' is not of type `nixcloudTLSModeType'.
#    - this error message contains a BUG, as it states nixcloud.TLS.certs.example.com.mode instead of nixcloud.TLS.certs."example.com".mode
#    - custom types should have a name close to the type definition. in this example a user seeing this error message will get confused as
#      he does not know what is going on as he can't guess the internals
#    - that is why i hacked the name to be: `name = "nixcloud.TLS.certs.<name?>.mode";`
#  - check: in check one uses isString, it would be nice to also be able to use the same syntax as in
#    type = types.string (and similar functions) becase now one has to reimplement basically what we 
#    have in type already
#  - merge: explain `merge = loc: defs: ` with an easy example. especially point out builtins.trace and lib.traceVal usage ...
#  - merge: explain the bool merge vs. the string vs. the str merge (see domain/email option implications)
#  - merge: default values for mkOption(s) don't appear in the merge function arguments
#    - this means one can't easily add a domain name based on the 'submodule' functiosn 'name' argument as it won't appear
#      in the merge when some other module defines it.
#    - it also means that we can't bail out in the 'merge' function with an error: you forgot to define a meaningful value here
#      this is why nixcloud.TLS.certs.<name?>'s apply function has assertions for that (hack!)
#  - undefined values: in the option system produce this error:
#    error: The option `nixcloud.TLS.certs.example.com.mode' is used but not defined.
#    but it lacks a context where that 'usage' actually takes place
#  - explain: `apply = ` hack to assert that at last one module set this option
#
# idea: test if the check function can be used with `types.string.check`
#      || (types.string.check x && x == "ACME") 
#       and how this can be done with submodule and similar types

# https://trello.com/c/dHSQhPYx/180-nixcloudtls
{ config, pkgs, lib, ... } @ args:
with lib;

let
  cfg = config.nixcloud.TLS;
  tls_certificateSetModule = {
    options = {
      tls_certificate = mkOption {
        type = types.path;
        description = ''
          A location containg the full path and filename to `/path/to/fullchain.pem`.
        '';
        example = "/path/to/fullchain.pem";
      };
      tls_certificate_key = mkOption {
        type = types.path;
        description = ''
          A location containg the full path and filename to `/path/to/key.pem`.
        '';
        example = "/path/to/key.pem";
      };
    };
  };
  nixcloudTLSDomainType = mkOptionType {
    name = "nixcloud.TLS.certs.<name?>.domain";
    check = x: (isString x && x != "") 
      || (isNull x);
    merge = mergeEqualOption;
  };
  nixcloudTLSEmailType = mkOptionType {
    name = "nixcloud.TLS.certs.<name?>.email";
    check = x: (isString x && x != "") 
      || (isNull x);
    merge = mergeEqualOption;
  };  
  nixcloudTLSModeType = mkOptionType {
    name = "nixcloud.TLS.certs.<name?>.mode";
    #description = "FIXME"; # FIXME <- what is that descripton good for?
    merge = mergeEqualOption;
    # FIXME this check is not 100% the same as the type previously was...
    # -> types.either (types.enum [ "ACME" "selfsigned" ]) (types.submodule tls_certificateSetModule);
    check = x: ((isString x && x == "ACME") 
        || (isString x && x == "selfsigned") 
        || ((isAttrs x || isFunction x) && x ? tls_certificate_key && x ? tls_certificate))
      || (isNull x);
  };
  c = x: ((isList x) && fold (el: c: if (isString el) then c else false) true x);
  m = loc: defs: unique (map (el: el.value) defs);
  nixcloudExtraDomainsType = mkOptionType {
    name = "nixcloud.TLS.certs.<name?>.extraDomains";
    check = c;
    merge = m;
  };
  nixcloudReloadType = mkOptionType {
    name = "nixcloud.TLS.certs.<name?>.reload";
    check = c;
    merge = m;
  };
  nixcloudRestartType = mkOptionType {
    name = "nixcloud.TLS.certs.<name?>.restart";
    check = c;
    merge = m;
  };  
  certOpts = { name, ... } @ toplevel: {
    options = {
      domain = mkOption {
        type = nixcloudTLSDomainType;
        default = null;
        apply = x: x;
        description = "Domain to fetch certificate for (defaults to the entry name)";
      };
      extraDomains = mkOption {
        type = nixcloudExtraDomainsType;
        default = [];
        example = literalExample ''
          [ "example.org" "mydomain.org" ];
        '';
        description = ''
          A list of extra domain names, which are included in the one certificate to be issued, with their
          own server roots if needed.
        '';
      };
      reload = mkOption {
        type = nixcloudReloadType;
        default = [];
        example = [ "postifx.service" ];
        description = "List of systemd services to reload when the certificate is being updated";
      };    
      restart = mkOption {
        type = nixcloudRestartType;
        default = [];
        example = [ "postifx.service" ];
        description = "List of systemd services to restart when the certificate is being updated";
      };  
      email = mkOption {
        type = nixcloudTLSEmailType;
        default = null;
        description = "Contact email address for the CA to be able to reach you when using ACME.";
      };
      mode = mkOption {
        type = nixcloudTLSModeType;
        default = null;
        description = ''
         Use this option to set the `TLS mode` to be used:
        
          * "ACME" - (default) uses let's encrypt to automatically download and install TLS certificates
          * "selfsigned" - this abstraction will create self signed certificates
          * { tls_certificate_key = /flux/to/cert.pem; tls_certificate = /flux/to/key.pem; }; - supply the certificates yourself
      ''; #'
 
      };
      tls_certificate_key = mkOption {
        type = types.path;
        readOnly = true;
        default = 
          if (builtins.typeOf toplevel.config.mode == "string") then 
            if (toplevel.config.mode == "ACME") then "/var/lib/acme/${name}/tlskey.pem" else "/var/lib/nixcloud/TLS/${name}/tlskey.pem"
          else 
            toplevel.config.mode.tls_certificate_key;
        description = "";
      };
      tls_certificate = mkOption {
        type = types.path;
        readOnly = true;
        default = 
          if (builtins.typeOf toplevel.config.mode == "string") then 
            if (toplevel.config.mode == "ACME") then "/var/lib/acme/${name}/tlscert.pem" else "/var/lib/nixcloud/TLS/${name}/tlscert.pem"
          else 
            toplevel.config.mode.tls_certificate;
        description = "";
      };        
    };
  };
in

{
  options = {
    nixcloud.TLS = {
      certs = mkOption {
        default = {};
        type = with types; attrsOf (submodule certOpts);
        apply = x: 
          let
            n = head (attrNames x);
          in
          # apply is also called with an empty set -> {} which is the default value assigned above (guess?)
          # and we have to make sure that the domain and mode is set properly so other modules can either 
          # expect this nixcloud.TLS.certs to be empty or filled with meaningful values
          assert (x == {} || x.${n}.mode != null) || abort "nixcloud.TLS.certs.\"${n}\".domain is undefined (`null`)!";
          assert (x == {} || x.${n}.mode != null) || abort "nixcloud.TLS.certs.\"${n}\".mode is undefined (`null`)!";
           x;
        description = ''
          Attribute set of certificates to get signed and renewed.
        '';
        example = literalExample ''

        '';
      };
    };
  };

  config = let
#     selfsignedService = {
#       description = "Create preliminary self-signed certificate for ${cert}";
#       preStart = ''
#           if [ ! -d '${cpath}' ]
#           then
#             mkdir -p '${cpath}'
#             chmod ${rights} '${cpath}'
#             chown '${data.user}:${data.group}' '${cpath}'
#           fi
#       '';
#       script = 
#         ''
#           # Create self-signed key
#           workdir="/run/acme-selfsigned-${cert}"
#           ${pkgs.openssl.bin}/bin/openssl genrsa -des3 -passout pass:x -out $workdir/server.pass.key 2048
#           ${pkgs.openssl.bin}/bin/openssl rsa -passin pass:x -in $workdir/server.pass.key -out $workdir/server.key
#           ${pkgs.openssl.bin}/bin/openssl req -new -key $workdir/server.key -out $workdir/server.csr \
#             -subj "/C=UK/ST=Warwickshire/L=Leamington/O=OrgName/OU=IT Department/CN=example.com"
#           ${pkgs.openssl.bin}/bin/openssl x509 -req -days 1 -in $workdir/server.csr -signkey $workdir/server.key -out $workdir/server.crt
#           # Move key to destination
#           mv $workdir/server.key ${cpath}/key.pem
#           mv $workdir/server.crt ${cpath}/fullchain.pem
#           # Create full.pem for e.g. lighttpd (same format as "simp_le ... -f full.pem" creates)
#           cat "${cpath}/key.pem" "${cpath}/fullchain.pem" > "${cpath}/full.pem"
#           # Clean up working directory
#           rm $workdir/server.csr
#           rm $workdir/server.pass.key
#           # Give key acme permissions
#           chmod ${rights} '${cpath}/key.pem'
#           chown '${data.user}:${data.group}' '${cpath}/key.pem'
#           chmod ${rights} '${cpath}/fullchain.pem'
#           chown '${data.user}:${data.group}' '${cpath}/fullchain.pem'
#           chmod ${rights} '${cpath}/full.pem'
#           chown '${data.user}:${data.group}' '${cpath}/full.pem'
#         '';
#       serviceConfig = {
#         Type = "oneshot";
#         RuntimeDirectory = "acme-selfsigned-${cert}";
#         PermissionsStartOnly = true;
#         User = data.user;
#         Group = data.group;
#       };
#       unitConfig = {
#         # Do not create self-signed key when key already exists
#         ConditionPathExists = "!${cpath}/key.pem";
#       };
#       before = [
#         "acme-selfsigned-certificates.target"
#       ];
#       wantedBy = [
#         "acme-selfsigned-certificates.target"
#       ];
#     };
  in {
    security.acme.certs = (fold (el: con: if ((config.nixcloud.TLS.certs.${el}.mode) == "ACME") then con // {
      "${el}" = let t = config.nixcloud.TLS.certs.${el}; in { 
        domain = "${t.domain}";
        #email = FIXME
        webroot = "/var/lib/acme/acme-challenges";
        postRun = ''
          systemctl reload nixcloud.TLS
        '';
      };
    } else con) {} (attrNames config.nixcloud.TLS.certs));

#       systemd.services."nixcloud.reverse-proxy" = let
#         acmeIsUsed = fold (el: con: (el == "ACME") || con) false (attrValues ACMEsupportSet);
#       in {
#         description   = "nixcloud reverse-proxy service";
#         wantedBy      = [ "multi-user.target" ];
#         
#         after = if acmeIsUsed then [ "acme-selfsigned-certificates.target" ] else [ "network.target" ];
#         wants =  if acmeIsUsed then [ "acme-selfsigned-certificates.target" "acme-certificates.target" ] else [];
#         
#         stopIfChanged = false;
# 
#         preStart = ''
#           mkdir -p ${stateDir}/nginx/logs
#           mkdir -p ${stateDir}/nginx
#           chmod 700 ${stateDir}
#           chown -R ${user}:${group} ${stateDir}
#         '';
#         serviceConfig = {
#           ExecStart = "${pkgs.nginx}/bin/nginx -c ${if (cfg.configFile == null) then (checkAndFormatNginxConfigfile {inherit configFile; fileName = "nixcloud.reverse-proxy.conf";}) else cfg.configFile}/nixcloud.reverse-proxy.conf -p ${stateDir}/nginx";
#           ExecReload = "${pkgs.coreutils}/bin/kill -HUP $MAINPID";
#           Restart = "always";
#           RestartSec = "10s";
#           StartLimitInterval = "1min";
#         };
#       };


    };
  meta = {
    maintainers = with lib.maintainers; [ qknight ];
  };
  
  
  #nixcloud.tests.wanted = [ ./test.nix ];
}


 
# # motivation
# 
# nixcloud.TLS - an abstraction to configure TLS with ease
# 
# # links
# https://github.com/NixOS/nixpkgs/pull/34388
# 
# https://github.com/NixOS/nixpkgs/blob/release-18.03/nixos/modules/security/acme.nix
# 
# # requirements
# 
# * supported modes
#         * "selfsigned"
#         * "ACME"
#         * {tls_certificate_key = ./path/key.pem; tls_certificate = ./path/cert.pem }
# * reverse-proxy / nixcloud.email must wait until targets are ready, so 
#         nixcloud.TLS."nixcloud.io".systemd.before
#         nixcloud.TLS."nixcloud.io".systemd.wantedBy
# 
# # usage examples

## von irgendwo:

# nixcloud.TLS."example.com123" = {
#   domain = "example.com";
#   mode = "selfsigned";
# };
# 
# nixcloud.TLS."example.org" = {
#   mode = {
#     ssl_certificate_key = /path/to/cert.pem;
#     ssl_certificate = /path/to/key.pem;
#   };
# };
# 
# nixcloud.TLS."nixcloud.io".services =
#   {
#     postfix.action = "restart";
#     dovecot.action = "reload";
#   };
#   
# # später dann (um den merge zu zeigen):
# 
# nixcloud.TLS."nixcloud.io".services =
#   {
#     "nixcloud.reverse-proxy".action = "reload";
#   };
#   
# # when using the cert location:
# 
# config.nixcloud.TLS."nixcloud.io".ssl_certificate -> /path/to/cert.pem
# config.nixcloud.TLS."nixcloud.io".ssl_certificate_key -> /path/to/key.pem
# 
# # oder auch folgende idee:
# 
#   nixcloud.webservices.leaps.z2 = {
#     enable = true;
#     proxyOptions = {
#       port = 3031;
#       http.mode = "on";
#       https.mode = "on";
#       path = "/flubber99";
#       domain = "foo.com";
#       # mit eigenem cert
#       TLS = {
#         ssl_certificate_key = /path/to/cert.pem;
#         ssl_certificate = /path/to/key.pem;
#       };
#       # klassisch
#       TLS = "ACME"; 
#       # paul: wir nutzen immer nixcloud.TLS und übergeben nur den identifier
#       TLS = "example22.com"; -> ist doof weil wir zwischen "ACME" | "none" | "einer domain" unterscheiden müssen
#       # ist das ne gute syntax?
#       TLS = nixcloud.TLS."example22.com"; -> gewinner: wir haben entweder builtins.typeOf "string" oder "set"
#                                              und bei set schauen wir ob ssl_certificate / ssl_certificate_key gesetzt ist
#     };
#   };
# 